const fs = require('fs');
const path = require('path');

// 1. Get input and output file paths from arguments
let jsonFilePath = process.argv[2];
let htmlFilePath = process.argv[3];

if (!jsonFilePath) {
    // If no argument is provided, look for the latest json file in the current directory
    const files = fs.readdirSync(process.cwd());
    const jsonFiles = files.filter(f => f.startsWith('webrtc_stats_') && f.endsWith('.json'));
    
    if (jsonFiles.length > 0) {
        // Sort by modification time to get the latest
        jsonFiles.sort((a, b) => {
            return fs.statSync(path.join(process.cwd(), b)).mtime.getTime() - 
                   fs.statSync(path.join(process.cwd(), a)).mtime.getTime();
        });
        jsonFilePath = path.join(process.cwd(), jsonFiles[0]);
        console.log(`🔍 No file specified. Automatically using the latest stats file: ${jsonFiles[0]}`);
    } else {
        console.error('❌ Error: Please specify the path to the stats JSON file.');
        console.error('Usage: node analyze_stats.js [path_to_json_file] [output_html_file]');
        process.exit(1);
    }
}

if (!htmlFilePath) {
    const parsedPath = path.parse(jsonFilePath);
    htmlFilePath = path.join(parsedPath.dir, `${parsedPath.name}_report.html`);
}

// 2. Read and parse the JSON file
let rawData;
try {
    rawData = fs.readFileSync(jsonFilePath, 'utf8');
} catch (e) {
    console.error(`❌ Error reading file: ${jsonFilePath}`);
    process.exit(1);
}

let reports;
try {
    reports = JSON.parse(rawData);
} catch (e) {
    console.error('❌ Error parsing JSON file. Make sure it is a valid JSON array of reports.');
    process.exit(1);
}

if (!Array.isArray(reports) || reports.length === 0) {
    console.error('❌ Error: JSON must be a non-empty array of statistics reports.');
    process.exit(1);
}

// Sort reports by timestamp to ensure chronological order
reports.sort((a, b) => (a.timestampUs || 0) - (b.timestampUs || 0));

// 3. Process time-series statistics
const startTimestampUs = reports[0].timestampUs;
const dataPoints = [];

let prevOutbound = null;
let prevRemoteInbound = null;

reports.forEach((report, index) => {
    const stats = report.statistics;
    if (!stats) return;

    const timestampSec = (report.timestampUs - startTimestampUs) / 1000000;
    
    // Find active transport and candidate-pair
    let activeCandidatePair = null;
    let selectedPairId = null;
    
    for (const key in stats) {
        if (stats[key].type === 'transport') {
            selectedPairId = stats[key].values.selectedCandidatePairId;
            break;
        }
    }
    
    if (selectedPairId && stats[selectedPairId]) {
        activeCandidatePair = stats[selectedPairId].values;
    } else {
        // Fallback: find nominated or succeeded candidate pair
        for (const key in stats) {
            if (stats[key].type === 'candidate-pair' && 
                (stats[key].values.nominated === 1 || stats[key].values.state === 'succeeded')) {
                activeCandidatePair = stats[key].values;
                break;
            }
        }
    }
    
    // Find outbound-rtp (video)
    let outboundRtp = null;
    for (const key in stats) {
        if (stats[key].type === 'outbound-rtp' && stats[key].values.kind === 'video') {
            outboundRtp = stats[key].values;
            break;
        }
    }
    
    // Find remote-inbound-rtp (video)
    let remoteInboundRtp = null;
    for (const key in stats) {
        if (stats[key].type === 'remote-inbound-rtp' && stats[key].values.kind === 'video') {
            remoteInboundRtp = stats[key].values;
            break;
        }
    }
    
    // Find media-source (video)
    let mediaSource = null;
    for (const key in stats) {
        if (stats[key].type === 'media-source' && stats[key].values.kind === 'video') {
            mediaSource = stats[key].values;
            break;
        }
    }

    // Calculate rates (delta / delta_time)
    let sendBitrateKbps = 0;
    let packetLossRate = 0;
    let avgQp = null;
    let avgEncodeTimeMs = null;
    let frameRate = outboundRtp ? outboundRtp.framesPerSecond : (mediaSource ? mediaSource.framesPerSecond : null);
    
    if (index > 0 && dataPoints.length > 0) {
        const prevPoint = dataPoints[dataPoints.length - 1];
        const dt = timestampSec - prevPoint.timestampSec;
        
        if (dt > 0) {
            if (outboundRtp && prevOutbound) {
                // Bitrate
                const bytesSentDiff = (outboundRtp.bytesSent || 0) - (prevOutbound.bytesSent || 0);
                sendBitrateKbps = Math.max(0, (bytesSentDiff * 8) / 1000 / dt);
                
                // Average QP
                const qpSumDiff = (outboundRtp.qpSum || 0) - (prevOutbound.qpSum || 0);
                const framesEncodedDiff = (outboundRtp.framesEncoded || 0) - (prevOutbound.framesEncoded || 0);
                if (framesEncodedDiff > 0) {
                    avgQp = Math.max(0, qpSumDiff / framesEncodedDiff);
                }
                
                // Average Encode Time
                const encodeTimeDiff = (outboundRtp.totalEncodeTime || 0) - (prevOutbound.totalEncodeTime || 0);
                if (framesEncodedDiff > 0) {
                    avgEncodeTimeMs = Math.max(0, (encodeTimeDiff / framesEncodedDiff) * 1000);
                }
            }
            
            if (remoteInboundRtp && prevRemoteInbound && outboundRtp && prevOutbound) {
                // Packet Loss Rate
                const packetsLostDiff = (remoteInboundRtp.packetsLost || 0) - (prevRemoteInbound.packetsLost || 0);
                const packetsSentDiff = (outboundRtp.packetsSent || 0) - (prevOutbound.packetsSent || 0);
                if (packetsSentDiff > 0) {
                    packetLossRate = Math.max(0, (packetsLostDiff / packetsSentDiff) * 100);
                }
            }
        }
    }

    // Prepare data point object
    dataPoints.push({
        timeLabel: `${Math.round(timestampSec)}s`,
        timestampSec: timestampSec,
        sendBitrateKbps: Math.round(sendBitrateKbps),
        availableOutgoingBitrateKbps: activeCandidatePair && activeCandidatePair.availableOutgoingBitrate ? 
            Math.round(activeCandidatePair.availableOutgoingBitrate / 1000) : null,
        targetBitrateKbps: outboundRtp && outboundRtp.targetBitrate ? 
            Math.round(outboundRtp.targetBitrate / 1000) : null,
        rttMs: activeCandidatePair && activeCandidatePair.currentRoundTripTime ? 
            Math.round(activeCandidatePair.currentRoundTripTime * 1000) : 
            (remoteInboundRtp && remoteInboundRtp.roundTripTime ? Math.round(remoteInboundRtp.roundTripTime * 1000) : null),
        jitterMs: remoteInboundRtp && remoteInboundRtp.jitter ? 
            Number((remoteInboundRtp.jitter * 1000).toFixed(2)) : null,
        packetLossRate: Number(packetLossRate.toFixed(2)),
        fps: frameRate || 0,
        width: outboundRtp ? outboundRtp.frameWidth || null : (mediaSource ? mediaSource.width || null : null),
        height: outboundRtp ? outboundRtp.frameHeight || null : (mediaSource ? mediaSource.height || null : null),
        avgQp: avgQp ? Number(avgQp.toFixed(1)) : null,
        avgEncodeTimeMs: avgEncodeTimeMs ? Number(avgEncodeTimeMs.toFixed(1)) : null,
        qualityLimitationReason: outboundRtp ? outboundRtp.qualityLimitationReason || 'none' : 'none',
        cpuUsage: (report.cpuUsage !== undefined && report.cpuUsage !== null) ? Number(report.cpuUsage.toFixed(1)) : null,
        memoryUsage: (report.memoryUsage !== undefined && report.memoryUsage !== null) ? Number(report.memoryUsage.toFixed(1)) : null
    });

    if (outboundRtp) prevOutbound = outboundRtp;
    if (remoteInboundRtp) prevRemoteInbound = remoteInboundRtp;
});

// 4. Calculate Summary Statistics
const summary = {
    totalDurationSec: Math.round((reports[reports.length - 1].timestampUs - startTimestampUs) / 1000000),
    avgBitrateKbps: 0,
    maxBitrateKbps: 0,
    avgRttMs: 0,
    avgFps: 0,
    maxFps: 0,
    avgJitterMs: 0,
    totalPacketsLost: 0,
    avgQp: 0,
    avgCpu: 0,
    maxCpu: 0,
    avgMem: 0,
    maxMem: 0,
    qualityLimitationReasons: { none: 0, cpu: 0, bandwidth: 0, other: 0 }
};

let validBitrateCount = 0;
let bitrateSum = 0;
let validRttCount = 0;
let rttSum = 0;
let validFpsCount = 0;
let fpsSum = 0;
let validJitterCount = 0;
let jitterSum = 0;
let validQpCount = 0;
let qpSum = 0;
let validCpuCount = 0;
let cpuSum = 0;
let validMemCount = 0;
let memSum = 0;

dataPoints.forEach(dp => {
    if (dp.sendBitrateKbps !== null && dp.sendBitrateKbps > 0) {
        bitrateSum += dp.sendBitrateKbps;
        validBitrateCount++;
        if (dp.sendBitrateKbps > summary.maxBitrateKbps) {
            summary.maxBitrateKbps = dp.sendBitrateKbps;
        }
    }
    if (dp.rttMs !== null) {
        rttSum += dp.rttMs;
        validRttCount++;
    }
    if (dp.fps !== null) {
        fpsSum += dp.fps;
        validFpsCount++;
        if (dp.fps > summary.maxFps) {
            summary.maxFps = dp.fps;
        }
    }
    if (dp.jitterMs !== null) {
        jitterSum += dp.jitterMs;
        validJitterCount++;
    }
    if (dp.avgQp !== null) {
        qpSum += dp.avgQp;
        validQpCount++;
    }
    if (dp.cpuUsage !== null) {
        cpuSum += dp.cpuUsage;
        validCpuCount++;
        if (dp.cpuUsage > summary.maxCpu) {
            summary.maxCpu = dp.cpuUsage;
        }
    }
    if (dp.memoryUsage !== null) {
        memSum += dp.memoryUsage;
        validMemCount++;
        if (dp.memoryUsage > summary.maxMem) {
            summary.maxMem = dp.memoryUsage;
        }
    }
    
    // Count quality limitation reasons
    const reason = dp.qualityLimitationReason || 'none';
    if (summary.qualityLimitationReasons[reason] !== undefined) {
        summary.qualityLimitationReasons[reason]++;
    } else {
        summary.qualityLimitationReasons.other++;
    }
});

summary.avgBitrateKbps = validBitrateCount > 0 ? Math.round(bitrateSum / validBitrateCount) : 0;
summary.avgRttMs = validRttCount > 0 ? Math.round(rttSum / validRttCount) : 0;
summary.avgFps = validFpsCount > 0 ? Math.round(fpsSum / validFpsCount) : 0;
summary.avgJitterMs = validJitterCount > 0 ? Number((jitterSum / validJitterCount).toFixed(2)) : 0;
summary.avgQp = validQpCount > 0 ? Number((qpSum / validQpCount).toFixed(1)) : 0;
summary.avgCpu = validCpuCount > 0 ? Number((cpuSum / validCpuCount).toFixed(1)) : null;
summary.avgMem = validMemCount > 0 ? Number((memSum / validMemCount).toFixed(1)) : null;

// Get total packet loss from last report
const lastReport = reports[reports.length - 1].statistics;
for (const key in lastReport) {
    if (lastReport[key].type === 'remote-inbound-rtp' && lastReport[key].values.kind === 'video') {
        summary.totalPacketsLost = lastReport[key].values.packetsLost || 0;
        break;
    }
}

// 5. Generate beautiful HTML content with Chart.js
const hasResourceStats = summary.avgCpu !== null && summary.avgCpu > 0;
const htmlContent = `
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>WebRTC 통계 분석 리포트</title>
    <!-- Chart.js CDN -->
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        :root {
            --bg-color: #0f172a;
            --card-bg: #1e293b;
            --text-color: #f8fafc;
            --text-muted: #94a3b8;
            --primary: #38bdf8;
            --success: #34d399;
            --warning: #fbbf24;
            --danger: #f87171;
            --border: #334155;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            background-color: var(--bg-color);
            color: var(--text-color);
            margin: 0;
            padding: 24px;
        }

        .container {
            max-width: 1400px;
            margin: 0 auto;
        }

        header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            border-bottom: 1px solid var(--border);
            padding-bottom: 20px;
            margin-bottom: 30px;
        }

        h1 {
            font-size: 28px;
            margin: 0;
            background: linear-gradient(135deg, var(--primary), var(--success));
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }

        .meta-info {
            font-size: 14px;
            color: var(--text-muted);
            text-align: right;
        }

        /* Dashboard Summary Grid */
        .summary-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }

        .summary-card {
            background-color: var(--card-bg);
            border: 1px solid var(--border);
            border-radius: 12px;
            padding: 20px;
            box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1);
            transition: transform 0.2s, box-shadow 0.2s;
        }

        .summary-card:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 15px -3px rgb(0 0 0 / 0.3), 0 4px 6px -4px rgb(0 0 0 / 0.3);
        }

        .summary-title {
            font-size: 14px;
            color: var(--text-muted);
            margin-bottom: 8px;
            text-transform: uppercase;
            letter-spacing: 0.05em;
        }

        .summary-value {
            font-size: 28px;
            font-weight: 700;
            color: var(--text-color);
        }

        .summary-unit {
            font-size: 14px;
            font-weight: 400;
            color: var(--text-muted);
            margin-left: 4px;
        }

        /* Charts Grid */
        .charts-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 24px;
        }

        @media (max-width: 1024px) {
            .charts-grid {
                grid-template-columns: 1fr;
            }
        }

        .chart-card {
            background-color: var(--card-bg);
            border: 1px solid var(--border);
            border-radius: 16px;
            padding: 24px;
            box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1);
            height: 420px;
            display: flex;
            flex-direction: column;
            box-sizing: border-box;
        }

        .chart-body {
            position: relative;
            flex-grow: 1;
            width: 100%;
            min-height: 0;
        }

        .chart-title {
            font-size: 18px;
            font-weight: 600;
            margin-top: 0;
            margin-bottom: 20px;
            border-left: 4px solid var(--primary);
            padding-left: 10px;
        }

        /* Quality Limitation Card styling */
        .limitation-card {
            grid-column: span 2;
        }
        @media (max-width: 1024px) {
            .limitation-card {
                grid-column: span 1;
            }
        }

        .limitation-grid {
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 16px;
            text-align: center;
        }

        .limitation-item {
            background-color: rgba(255, 255, 255, 0.03);
            border-radius: 8px;
            padding: 15px;
            border: 1px dashed var(--border);
        }

        .limitation-label {
            font-size: 13px;
            color: var(--text-muted);
            margin-bottom: 6px;
        }

        .limitation-count {
            font-size: 24px;
            font-weight: bold;
        }

        .badge {
            display: inline-block;
            padding: 2px 8px;
            border-radius: 9999px;
            font-size: 12px;
            font-weight: 500;
        }
        .badge-none { background-color: rgba(52, 211, 153, 0.15); color: var(--success); }
        .badge-cpu { background-color: rgba(248, 113, 113, 0.15); color: var(--danger); }
        .badge-bandwidth { background-color: rgba(251, 191, 36, 0.15); color: var(--warning); }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <div>
                <h1>📊 WebRTC Real-time Statistics Report</h1>
                <p style="color: var(--text-muted); margin: 5px 0 0 0;">WebRTC 연결 정보 및 비디오 송출 성능 통계 분석</p>
            </div>
            <div class="meta-info">
                <div>대상 파일: <strong>${path.basename(jsonFilePath)}</strong></div>
                <div>총 측정 시간: <strong>${summary.totalDurationSec}초</strong> (스냅샷 개수: ${reports.length}개)</div>
            </div>
        </header>

        <!-- Dashboard Summary Grid -->
        <div class="summary-grid">
            <div class="summary-card">
                <div class="summary-title">평균 송출 속도</div>
                <div class="summary-value">${summary.avgBitrateKbps.toLocaleString()}<span class="summary-unit">Kbps</span></div>
            </div>
            <div class="summary-card">
                <div class="summary-title">최대 송출 속도</div>
                <div class="summary-value">${summary.maxBitrateKbps.toLocaleString()}<span class="summary-unit">Kbps</span></div>
            </div>
            <div class="summary-card">
                <div class="summary-title">평균 왕복 지연 시간 (RTT)</div>
                <div class="summary-value" style="color: \${summary.avgRttMs > 100 ? 'var(--warning)' : 'var(--text-color)'}">${summary.avgRttMs}<span class="summary-unit">ms</span></div>
            </div>
            <div class="summary-card">
                <div class="summary-title">평균 프레임레이트 (FPS)</div>
                <div class="summary-value">${summary.avgFps}<span class="summary-unit">fps</span></div>
            </div>
            <div class="summary-card">
                <div class="summary-title">총 패킷 손실</div>
                <div class="summary-value" style="color: \${summary.totalPacketsLost > 0 ? 'var(--danger)' : 'var(--success)'}">${summary.totalPacketsLost.toLocaleString()}<span class="summary-unit">개</span></div>
            </div>
            <div class="summary-card">
                <div class="summary-title">평균 화질 압축률 (QP)</div>
                <div class="summary-value">${summary.avgQp}<span class="summary-unit">QP</span></div>
            </div>
            ${hasResourceStats ? `
            <div class="summary-card">
                <div class="summary-title">평균 CPU 사용량</div>
                <div class="summary-value" style="color: var(--primary);">${summary.avgCpu}<span class="summary-unit">%</span></div>
            </div>
            <div class="summary-card">
                <div class="summary-title">최대 CPU 사용량</div>
                <div class="summary-value" style="color: var(--primary);">${summary.maxCpu}<span class="summary-unit">%</span></div>
            </div>
            <div class="summary-card">
                <div class="summary-title">평균 메모리 점유</div>
                <div class="summary-value" style="color: var(--success);">${summary.avgMem}<span class="summary-unit">MB</span></div>
            </div>
            <div class="summary-card">
                <div class="summary-title">최대 메모리 점유</div>
                <div class="summary-value" style="color: var(--success);">${summary.maxMem}<span class="summary-unit">MB</span></div>
            </div>
            ` : ''}
        </div>

        <!-- Charts Grid -->
        <div class="charts-grid">
            <!-- Chart 1: Bitrate -->
            <div class="chart-card">
                <h3 class="chart-title">대역폭 및 비트레이트</h3>
                <div class="chart-body">
                    <canvas id="bitrateChart"></canvas>
                </div>
            </div>

            <!-- Chart 2: Network Quality -->
            <div class="chart-card">
                <h3 class="chart-title">지연 시간 (RTT) & 지터</h3>
                <div class="chart-body">
                    <canvas id="latencyChart"></canvas>
                </div>
            </div>

            <!-- Chart 3: Frame Rate & Loss -->
            <div class="chart-card">
                <h3 class="chart-title">프레임레이트 (FPS) & 패킷 손실률</h3>
                <div class="chart-body">
                    <canvas id="fpsLossChart"></canvas>
                </div>
            </div>

            <!-- Chart 4: Video Quality & Encoding -->
            <div class="chart-card">
                <h3 class="chart-title">화질 지수 (QP) & 인코딩 시간</h3>
                <div class="chart-body">
                    <canvas id="qualityChart"></canvas>
                </div>
            </div>

            ${hasResourceStats ? `
            <!-- Chart 5: System Resources -->
            <div class="chart-card">
                <h3 class="chart-title">디바이스 리소스 사용량 (CPU & Memory)</h3>
                <div class="chart-body">
                    <canvas id="resourceChart"></canvas>
                </div>
            </div>
            ` : ''}

            <!-- Card 5: Quality Limitation Info -->
            <div class="chart-card limitation-card">
                <h3 class="chart-title">비디오 화질 성능 제한 원인 분석</h3>
                <div style="margin-bottom: 20px; font-size: 14px; color: var(--text-muted);">
                    네트워크 대역폭이나 디바이스의 연산 파워(CPU) 부족으로 인해 화질 및 프레임이 제약을 받은 횟수를 나타냅니다.
                </div>
                <div class="limitation-grid">
                    <div class="limitation-item">
                        <div class="limitation-label"><span class="badge badge-none">None</span> 제한 없음 (정상)</div>
                        <div class="limitation-count" style="color: var(--success);">${summary.qualityLimitationReasons.none}회</div>
                    </div>
                    <div class="limitation-item">
                        <div class="limitation-label"><span class="badge badge-bandwidth">Bandwidth</span> 대역폭 부족</div>
                        <div class="limitation-count" style="color: var(--warning);">${summary.qualityLimitationReasons.bandwidth}회</div>
                    </div>
                    <div class="limitation-item">
                        <div class="limitation-label"><span class="badge badge-cpu">CPU</span> CPU 리소스 한계</div>
                        <div class="limitation-count" style="color: var(--danger);">${summary.qualityLimitationReasons.cpu}회</div>
                    </div>
                    <div class="limitation-item">
                        <div class="limitation-label">기타 이유</div>
                        <div class="limitation-count" style="color: var(--text-muted);">${summary.qualityLimitationReasons.other}회</div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- Chart Configuration Script -->
    <script>
        const chartData = ${JSON.stringify(dataPoints)};
        
        const labels = chartData.map(dp => dp.timeLabel);
        
        // Configuration helper
        Chart.defaults.color = '#94a3b8';
        Chart.defaults.borderColor = '#334155';
        
        // 1. Bitrate Chart
        new Chart(document.getElementById('bitrateChart'), {
            type: 'line',
            data: {
                labels: labels,
                datasets: [
                    {
                        label: '실제 송출 속도 (Send Bitrate)',
                        data: chartData.map(dp => dp.sendBitrateKbps),
                        borderColor: '#38bdf8',
                        backgroundColor: 'rgba(56, 189, 248, 0.1)',
                        fill: true,
                        tension: 0.3
                    },
                    {
                        label: '가용 대역폭 (Available Bandwidth)',
                        data: chartData.map(dp => dp.availableOutgoingBitrateKbps),
                        borderColor: '#34d399',
                        borderDash: [5, 5],
                        fill: false,
                        tension: 0.1
                    },
                    {
                        label: '목표 비트레이트 (Target Bitrate)',
                        data: chartData.map(dp => dp.targetBitrateKbps),
                        borderColor: '#fbbf24',
                        borderDash: [2, 2],
                        fill: false,
                        tension: 0.1
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: {
                        title: { display: true, text: '비트레이트 (Kbps)' }
                    }
                }
            }
        });

        // 2. Latency Chart (RTT & Jitter)
        new Chart(document.getElementById('latencyChart'), {
            type: 'line',
            data: {
                labels: labels,
                datasets: [
                    {
                        label: '왕복 지연 시간 (RTT)',
                        data: chartData.map(dp => dp.rttMs),
                        borderColor: '#fbbf24',
                        backgroundColor: 'transparent',
                        tension: 0.2,
                        yAxisID: 'y'
                    },
                    {
                        label: '지터 (Jitter)',
                        data: chartData.map(dp => dp.jitterMs),
                        borderColor: '#a78bfa',
                        backgroundColor: 'transparent',
                        tension: 0.2,
                        yAxisID: 'y1'
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: {
                        type: 'linear',
                        display: true,
                        position: 'left',
                        title: { display: true, text: 'RTT (ms)' }
                    },
                    y1: {
                        type: 'linear',
                        display: true,
                        position: 'right',
                        grid: { drawOnChartArea: false },
                        title: { display: true, text: '지터 (ms)' }
                    }
                }
            }
        });

        // 3. FPS & Packet Loss Chart
        new Chart(document.getElementById('fpsLossChart'), {
            type: 'line',
            data: {
                labels: labels,
                datasets: [
                    {
                        label: '송출 프레임레이트 (FPS)',
                        data: chartData.map(dp => dp.fps),
                        borderColor: '#34d399',
                        backgroundColor: 'transparent',
                        tension: 0.1,
                        yAxisID: 'y'
                    },
                    {
                        label: '패킷 손실률 (Loss Rate)',
                        data: chartData.map(dp => dp.packetLossRate),
                        borderColor: '#f87171',
                        backgroundColor: 'rgba(248, 113, 113, 0.1)',
                        fill: true,
                        tension: 0.1,
                        yAxisID: 'y1'
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: {
                        type: 'linear',
                        display: true,
                        position: 'left',
                        title: { display: true, text: '프레임 레이트 (FPS)' },
                        min: 0
                    },
                    y1: {
                        type: 'linear',
                        display: true,
                        position: 'right',
                        grid: { drawOnChartArea: false },
                        title: { display: true, text: '패킷 손실률 (%)' },
                        min: 0,
                        max: Math.max(10, Math.max(...chartData.map(dp => dp.packetLossRate)) * 1.5)
                    }
                }
            }
        });

        // 4. Quality Chart (QP & Encode Time)
        new Chart(document.getElementById('qualityChart'), {
            type: 'line',
            data: {
                labels: labels,
                datasets: [
                    {
                        label: '화질 압축 지수 (QP) - 낮을수록 화질 우수',
                        data: chartData.map(dp => dp.avgQp),
                        borderColor: '#f472b6',
                        backgroundColor: 'transparent',
                        tension: 0.2,
                        yAxisID: 'y'
                    },
                    {
                        label: '프레임당 인코딩 지연',
                        data: chartData.map(dp => dp.avgEncodeTimeMs),
                        borderColor: '#fb7185',
                        backgroundColor: 'transparent',
                        tension: 0.2,
                        yAxisID: 'y1'
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: {
                        type: 'linear',
                        display: true,
                        position: 'left',
                        title: { display: true, text: 'QP 지수' }
                    },
                    y1: {
                        type: 'linear',
                        display: true,
                        position: 'right',
                        grid: { drawOnChartArea: false },
                        title: { display: true, text: '인코딩 시간 (ms)' }
                    }
                }
            }
        });

        ${hasResourceStats ? `
        // 5. System Resources Chart
        new Chart(document.getElementById('resourceChart'), {
            type: 'line',
            data: {
                labels: labels,
                datasets: [
                    {
                        label: 'CPU 사용량 (%)',
                        data: chartData.map(dp => dp.cpuUsage),
                        borderColor: '#38bdf8',
                        backgroundColor: 'rgba(56, 189, 248, 0.05)',
                        fill: true,
                        tension: 0.2,
                        yAxisID: 'y'
                    },
                    {
                        label: '메모리 점유 (MB)',
                        data: chartData.map(dp => dp.memoryUsage),
                        borderColor: '#34d399',
                        backgroundColor: 'transparent',
                        tension: 0.2,
                        yAxisID: 'y1'
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: {
                        type: 'linear',
                        display: true,
                        position: 'left',
                        title: { display: true, text: 'CPU 사용량 (%)' },
                        min: 0
                    },
                    y1: {
                        type: 'linear',
                        display: true,
                        position: 'right',
                        grid: { drawOnChartArea: false },
                        title: { display: true, text: '메모리 점유 (MB)' },
                        min: 0
                    }
                }
            }
        });
        ` : ''}
    </script>
</body>
</html>
`;

// 6. Write HTML file to disk
try {
    fs.writeFileSync(htmlFilePath, htmlContent, 'utf8');
    console.log(`✅ Success! Report generated successfully.`);
    console.log(`📂 HTML Report Location: ${htmlFilePath}`);
} catch (e) {
    console.error(`❌ Error writing HTML file: ${htmlFilePath}`);
    process.exit(1);
}
