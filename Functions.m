%% ============================================================
% LOCAL FUNCTIONS
% ============================================================

%% >>> DSP-FUNCTIONS-BEGIN

function y = spectral_denoise(x, Fs, P)
% Decision-directed Wiener filter with:
%   - initial noise profile from the quietest frames, refined from confirmedd pauses
%   - continuous minimum-statistics noise tracking (works while someone is talking)
%   - soft pause gate (quiets room tone between words, never a hard on/off switch)
    x  = x(:);
    N  = numel(x);
    frame_len = P.frame_len;
    hop       = P.hop;
    H         = frame_len/2 + 1;
    xp        = [x; zeros(frame_len, 1)];
    num_frames = floor((numel(xp) - frame_len)/hop) + 1;
    win  = sqrt(hann(frame_len, 'periodic'));
    win2 = win.^2;

    freqs     = (0:H-1)' * Fs/frame_len;
    gate_bins = freqs >= 250 & freqs <= 4000;
    hf_bins   = freqs >= 4000;

    % ---------- pass 1: frame energies ----------
    fprintf('  [%s] measuring noise and speech activity...\n', P.label);
    energy   = zeros(1, num_frames);
    gate_pow = zeros(1, num_frames);
    for k = 1:num_frames
        s   = (k-1)*hop + 1;
        X   = fft(xp(s:s+frame_len-1) .* win);
        Pw  = abs(X(1:H)).^2;
        energy(k)   = sum(Pw);
        gate_pow(k) = sum(Pw(gate_bins));
    end

    [~, sorted_index] = sort(energy);
    num_noise = max(1, round(0.02 * num_frames));
    noise_idx = sorted_index(1:num_noise);

    num_np = min(num_frames, max(5, round(P.noise_pct/100 * num_frames)));
    noise_base = zeros(H,1);
    for j = 1:num_np
        k  = sorted_index(j);
        s  = (k-1)*hop + 1;
        Xn = fft(xp(s:s+frame_len-1) .* win);
        noise_base = noise_base + abs(Xn(1:H)).^2;
    end
    noise_base = noise_base / num_np + eps;

    % soft speech gate  (0 = pause, 1 = speech)
    snr_db = 10*log10(gate_pow / (mean(gate_pow(noise_idx)) + eps) + eps);
    g0     = min(max((snr_db - P.gate_lo_db) / (P.gate_hi_db - P.gate_lo_db), 0), 1);
    lead   = round(P.gate_lead_s * Fs / hop);
    hold   = round(P.gate_hold_s * Fs / hop);
    ramp   = max(1, round(P.gate_ramp_s * Fs / hop));
    g1     = movmax(g0, [hold, lead]);
    gate   = movmean(g1, 2*floor(ramp/2) + 1);
    fprintf('  [%s] %.1f%% of the recording treated as pause.\n', P.label, 100*(1 - mean(gate)));

    % refine the noise profile with frames the gate confirms are pauses
    pause_frames = find(gate < 0.02);
    if numel(pause_frames) >= 20
        if numel(pause_frames) > 3000
            pause_frames = pause_frames(round(linspace(1, numel(pause_frames), 3000)));
        end
        nb_acc = zeros(H,1);
        for j = 1:numel(pause_frames)
            k  = pause_frames(j);
            s  = (k-1)*hop + 1;
            Xn = fft(xp(s:s+frame_len-1) .* win);
            nb_acc = nb_acc + abs(Xn(1:H)).^2;
        end
        noise_base = nb_acc / numel(pause_frames) + eps;
        fprintf('  [%s] noise profile refined from %d confirmed pause frames.\n', P.label, numel(pause_frames));
    end
    noise_base = movmean(noise_base, 5);
    clear energy gate_pow snr_db g0 g1 sorted_index;

    % ---------- pass 2: the filter ----------
    speech_floor = P.speech_floor_db * ones(H,1);
    speech_floor(hf_bins) = P.hf_floor_db;
    min_gain = 10 .^ (speech_floor/20);

    pause_g = P.pause_floor_db * ones(H,1);
    pause_g(hf_bins) = P.pause_floor_hf_db;
    pause_g = 10 .^ (pause_g/20);

    out  = zeros(numel(xp), 1);
    wsum = zeros(numel(xp), 1);

    G_prev   = ones(H,1);
    mag_prev = zeros(H,1);

    Psm       = noise_base;
    cur_min   = noise_base;
    sub_buf   = inf(H, P.ms_num_sub);
    sub_ptr   = 0;
    sub_cnt   = 0;
    ms_frames = max(1, round(P.ms_sub_s * Fs / hop));

    report_every = max(1, round(num_frames/5));
    fprintf('  [%s] filtering...\n', P.label);

    for k = 1:num_frames
        s = (k-1)*hop + 1;
        e = s + frame_len - 1;

        X   = fft(xp(s:e) .* win);
        Xh  = X(1:H);
        mag = abs(Xh);
        pw  = mag.^2;

        % --- noise estimate for THIS frame
        if P.ms_on
            Psm     = P.ms_smooth*Psm + (1 - P.ms_smooth)*pw;
            cur_min = min(cur_min, Psm);
            sub_cnt = sub_cnt + 1;
            if sub_cnt >= ms_frames
                sub_ptr = mod(sub_ptr, P.ms_num_sub) + 1;
                sub_buf(:, sub_ptr) = cur_min;
                cur_min = Psm;
                sub_cnt = 0;
            end
            ms_noise  = P.ms_bias * min(cur_min, min(sub_buf, [], 2));
            ms_noise  = min(ms_noise, P.ms_cap * noise_base);
            noise_est = max(ms_noise, P.base_weight * noise_base);
        else
            noise_est = noise_base;
        end
        noise_pwr = P.oversub * noise_est + eps;

        % --- decision-directed Wiener gain
        post_snr = pw ./ noise_pwr;
        prio_snr = P.alpha_dd * (G_prev.^2 .* mag_prev.^2 ./ noise_pwr) + ...
                   (1 - P.alpha_dd) * max(post_snr - 1, 0);

        gain = prio_snr ./ (prio_snr + 1);
        if P.gain_smooth_bins > 1
            gain = movmean(gain, P.gain_smooth_bins);
        end
        gain = gain .^ P.gain_power;
        gain = max(gain, min_gain);

        G_prev   = gain;
        mag_prev = mag;

        % --- soft pause gate blend
        gt   = gate(k);
        gain = (gain .^ gt) .* (pause_g .^ (1 - gt));

        % --- pause-based profile tracking (clamped so a word tail cannot drag it up)
        if P.noise_track && gt < 0.05
            noise_base = (1 - P.noise_track_rate) * noise_base + ...
                         P.noise_track_rate * min(pw, 4 * noise_base);
        end

        Yh = gain .* Xh;
        Y  = [Yh; conj(Yh(end-1:-1:2))];
        fr = real(ifft(Y)) .* win;

        out(s:e)  = out(s:e)  + fr;
        wsum(s:e) = wsum(s:e) + win2;

        if mod(k, report_every) == 0
            fprintf('  [%s] %3d%%\n', P.label, round(100*k/num_frames));
        end
    end

    valid = wsum > 1e-3;
    out(valid) = out(valid) ./ wsum(valid);
    y = out(1:N);
    y = y / (max(abs(y)) + eps);
end

function [gate, y] = voice_gate(y, Fs, hop, G)
% Decides, from the ALREADY CLEANED signal, where the professor is speaking,
% and pushes everything else down by G.pause_db.
%   - must be G.snr_db above the residual noise floor
%   - must not be more than G.dominant_db below the professor's normal level
%     (removes far-away voices, which are always quieter than the lecturer)
%   - blips shorter than G.min_speech_s are removed
    y = y(:);
    [zb, pb, kb] = butter(4, G.band/(Fs/2), 'bandpass');
    [sosb, gb]   = zp2sos(zb, pb, kb);
    yb  = filtfilt(sosb, gb, y);
    lvl = block_levels_db(yb, hop);
    clear yb;

    pw  = movmean(10.^(lvl/10), G.smooth_blocks);
    lvl = 10*log10(pw + 1e-12);

    floor_db = pct_sorted(lvl, 5);
    above    = lvl(lvl > floor_db + 12);
    if numel(above) >= 50
        ref_db = median(above);
    else
        ref_db = max(lvl);
    end
    thr = max(floor_db + G.snr_db, ref_db - G.dominant_db);
    fprintf('  residual floor %.1f dB | professor level %.1f dB | gate threshold %.1f dB\n', ...
            floor_db, ref_db, thr);

    g0     = double(lvl > thr);
    k_open = 2*floor(max(1, round(G.min_speech_s * Fs / hop))/2) + 1;
    g0     = movmax(movmin(g0, k_open), k_open);      % opening: drop tiny blips

    lead = round(G.lead_s * Fs / hop);
    hold = round(G.hold_s * Fs / hop);
    ramp = max(1, round(G.ramp_s * Fs / hop));
    g1   = movmax(g0, [hold, lead]);
    gate = movmean(g1, 2*floor(ramp/2) + 1);
    gate = min(max(gate, 0), 1);

    gain_db = G.pause_db * (1 - gate);
    y = apply_block_gain(y, 10.^(gain_db/20), hop);
end

function [y, ok] = neural_denoise(x, fs, passes, mix, chunk_s, ov_s)
% Audio Toolbox denoiseNet, chunked, optionally several passes.
% Returns ok = false (and the input unchanged) if the network is unavailable.
    x  = x(:);
    y  = x;
    ok = false;
    try
        net   = denoiseNet;
        dn_fs = 16000;
        if fs ~= dn_fs
            xr = resample(x, dn_fs, fs);
        else
            xr = x;
        end
        for p = 1:passes
            fprintf('  neural pass %d of %d ...\n', p, passes);
            xr = denoise_chunked(net, xr, dn_fs, chunk_s, ov_s);
        end
        if fs ~= dn_fs
            yn = resample(xr, fs, dn_fs);
        else
            yn = xr;
        end
        yn = fit_len(yn, numel(x));
        y  = (1 - mix) * x + mix * yn;
        ok = true;
        disp('  neural denoise applied.');
    catch ME
        warning('Neural denoise skipped (%s).', ME.message);
        y  = x;
        ok = false;
    end
end

function y = denoise_chunked(net, x, fs, chunk_s, ov_s)
    x = x(:);
    N = numel(x);
    C = round(chunk_s * fs);
    O = round(ov_s * fs);
    if N <= C
        y = fit_len(double(denoiseSpeech(net, x)), N);
        return;
    end
    y    = zeros(N, 1);
    fin  = ((0:O-1)' + 0.5) / O;       % fade-in and fade-out add up to exactly 1
    fout = flipud(fin);
    s = 1;
    n_chunks = 1 + ceil((N - C) / (C - O));
    idx = 0;
    while true
        e   = min(s + C - 1, N);
        seg = fit_len(double(denoiseSpeech(net, x(s:e))), e - s + 1);
        w   = ones(e - s + 1, 1);
        if s > 1, w(1:O)         = fin;  end
        if e < N, w(end-O+1:end) = fout; end
        y(s:e) = y(s:e) + seg .* w;
        idx = idx + 1;
        fprintf('    chunk %d/%d\n', idx, n_chunks);
        if e >= N, break; end
        s = s + C - O;
    end
end

function v = fit_len(v, n)
    v = v(:);
    if numel(v) >= n
        v = v(1:n);
    else
        v = [v; zeros(n - numel(v), 1)];
    end
end

function q = pct_sorted(v, p)
    s = sort(v(:));
    q = s(max(1, min(numel(s), round(p/100 * numel(s)))));
end

function r = ternary(cond, a, b)
    if cond, r = a; else, r = b; end
end

function tones = detect_tones(x, fs, min_db, fmin, fmax, max_n)
% Finds stationary hum/buzz lines using only the quietest parts of the
% recording, so speech harmonics don't get mistaken for noise tones.
    blk = round(0.5 * fs);
    nb  = floor(length(x) / blk);
    be  = zeros(1, nb);
    for b = 1:nb
        be(b) = sum(x((b-1)*blk+1 : b*blk).^2);
    end
    [~, ord] = sort(be);
    quiet_ids = sort(ord(1:min(nb, max(4, round(0.15 * nb)))));
    xq = zeros(blk * numel(quiet_ids), 1);
    for i = 1:numel(quiet_ids)
        b = quiet_ids(i);
        xq((i-1)*blk+1 : i*blk) = x((b-1)*blk+1 : b*blk);
    end
    nfft_t = 2^16;
    tones = [];
    if numel(xq) >= 2*nfft_t
        [Pq, fq] = pwelch(xq, hann(nfft_t, 'periodic'), nfft_t/2, nfft_t, fs);
        Pdb    = 10*log10(Pq + eps);
        df     = fq(2) - fq(1);
        excess = Pdb - movmedian(Pdb, 2*round(75/df) + 1);
        sel    = find(fq >= fmin & fq <= fmax);
        [pkv, loc] = findpeaks(excess(sel), 'MinPeakHeight', min_db, 'MinPeakDistance', 3);
        tones  = fq(sel(loc));
        if numel(tones) > max_n
            [~, order] = sort(pkv, 'descend');
            keep = sort(order(1:max_n));
            tones = tones(keep);
        end
        tones = tones(:).';
    end
end

function x = apply_fade(x, Fs, ms)
    F = min(round(ms/1000 * Fs), floor(numel(x)/2));
    if F < 2, return; end
    f = 0.5 * (1 - cos(pi*(0:F-1)'/(F-1)));
    x(1:F)         = x(1:F)         .* f;
    x(end-F+1:end) = x(end-F+1:end) .* flipud(f);
end

function y = level_and_master(x, Fs, is_speech, hop, LV)
    x  = x(:);
    N  = numel(x);
    nb = ceil(N / hop);
    sp = double(is_speech(1:min(nb, numel(is_speech))));
    sp(end+1:nb) = sp(end);
    sp = sp(:);
    lvl = block_levels_db(x, hop);
    W   = max(3, round(LV.level_win * Fs / hop));
    cur = speech_level_curve(lvl, sp, W);
    ok  = ~isnan(cur);
    if ~any(ok)
        warning('No speech detected - leveler skipped.');
        y = x;
    else
        ref = median(cur(ok));
        dev = ref - cur;
        dev = min(max(dev, -LV.max_cut_db), LV.max_boost_db);
        dev = fill_gaps(dev);
        if isfield(LV, 'no_pause_boost') && LV.no_pause_boost
            wsm   = max(1, round(0.3 * Fs / hop));
            openv = min(movmean(sp, wsm) * 1.5, 1);
            dev   = min(dev, LV.max_boost_db * openv);
        end
        dev = movmean(dev, max(1, round(0.2 * Fs / hop)));
        g_db = dev + (LV.target_dbfs - ref);
        y = apply_block_gain(x, 10.^(g_db/20), hop);
        fprintf('  Leveler     : typical speech level %.1f dBFS\n', ref);
    end
    clear x lvl cur;
    if LV.comp_ratio > 1
        y = dynamics_gain(y, Fs, LV.comp_thr_db, LV.comp_ratio, 5, 120, 5);
    end
    [L, ~] = measure_lufs(y, Fs);
    if isfinite(L) && L > -80
        y = y * 10^((LV.target_lufs - L) / 20);
    end
    y = dynamics_gain(y, Fs, LV.ceiling_dbfs - 0.5, 1000, 1, 100, 5);
    lim = 10^(LV.ceiling_dbfs / 20);
    y = max(min(y, lim), -lim);
end

function lvl = block_levels_db(x, hop)
    x   = x(:);
    N   = numel(x);
    nb  = ceil(N / hop);
    xp  = [x.^2; zeros(nb*hop - N, 1)];
    S   = sum(reshape(xp, hop, nb), 1)';
    cnt = hop * ones(nb, 1);
    cnt(end) = N - (nb-1)*hop;
    lvl = 10*log10(S ./ cnt + 1e-12);
end

function cur = speech_level_curve(lvl_db, sp, W)
    num = movmean(lvl_db(:) .* sp(:), W);
    den = movmean(sp(:), W);
    cur = num ./ max(den, eps);
    cur(den < 0.1) = NaN;
end

function v = fill_gaps(v)
    v  = v(:);
    k  = (1:numel(v))';
    ok = ~isnan(v);
    if all(ok), return; end
    if sum(ok) == 1
        v(:) = v(ok);
        return;
    end
    first = find(ok, 1, 'first');
    last  = find(ok, 1, 'last');
    v = interp1(k(ok), v(ok), k, 'linear');
    v(1:first)   = v(first);
    v(last:end)  = v(last);
end

function y = dynamics_gain(x, Fs, thr_db, ratio, att_ms, rel_ms, look_ms)
    x   = x(:);
    N   = numel(x);
    blk = max(1, round(0.002 * Fs));
    nb  = ceil(N / blk);
    pk = zeros(nb, 1);
    for k = 1:nb
        s = (k-1)*blk + 1;
        e = min(k*blk, N);
        pk(k) = max(abs(x(s:e)));
    end
    pk_db = 20*log10(pk + 1e-9);
    gr = -max(pk_db - thr_db, 0) * (1 - 1/ratio);
    L  = max(1, round((look_ms/1000) * Fs / blk));
    gr = movmin(gr, [1 L]);
    a_att = exp(-(blk/Fs) / (att_ms/1000));
    a_rel = exp(-(blk/Fs) / (rel_ms/1000));
    gs = zeros(nb, 1);
    cur = 0;
    for k = 1:nb
        if gr(k) < cur
            cur = a_att*cur + (1 - a_att)*gr(k);
        else
            cur = a_rel*cur + (1 - a_rel)*gr(k);
        end
        gs(k) = cur;
    end
    y = apply_block_gain(x, 10.^(gs/20), blk);
end

function y = apply_block_gain(x, g, blk)
    x  = x(:);
    g  = g(:);
    N  = numel(x);
    tc = [0; ((1:numel(g))' - 0.5) * blk; N + blk];
    gt = [g(1); g; g(end)];
    y  = zeros(N, 1);
    CH = 2^20;
    for s = 1:CH:N
        e = min(s + CH - 1, N);
        y(s:e) = x(s:e) .* interp1(tc, gt, (s:e)');
    end
end

function [L, unit] = measure_lufs(x, Fs)
    x    = x(:);
    unit = 'LUFS';
    try
        L = integratedLoudness(x, Fs);
        if ~isfinite(L), error('not finite'); end
    catch
        unit = 'dBFS RMS';
        L = 20*log10(sqrt(mean(x.^2)) + 1e-12);
    end
end

function [b, a] = peaking_eq(f0, Q, gain_db, Fs)
    A     = 10^(gain_db / 40);
    w0    = 2*pi*f0 / Fs;
    alpha = sin(w0) / (2*Q);
    b = [1 + alpha*A, -2*cos(w0), 1 - alpha*A];
    a = [1 + alpha/A, -2*cos(w0), 1 - alpha/A];
    b = b / a(1);
    a = a / a(1);
end

function [b, a] = high_shelf_eq(f0, gain_db, Fs)
% RBJ high-shelf EQ, S = 1.
    A  = 10^(gain_db / 40);
    w0 = 2*pi*f0 / Fs;
    S  = 1;
    al = sin(w0)/2 * sqrt((A + 1/A)*(1/S - 1) + 2);
    c  = cos(w0);

    b = [ A*((A+1) + (A-1)*c + 2*sqrt(A)*al), ...
         -2*A*((A-1) + (A+1)*c), ...
          A*((A+1) + (A-1)*c - 2*sqrt(A)*al)];

    a = [ (A+1) - (A-1)*c + 2*sqrt(A)*al, ...
          2*((A-1) - (A+1)*c), ...
          (A+1) - (A-1)*c - 2*sqrt(A)*al];

    b = b / a(1);
    a = a / a(1);
end

%% >>> DSP-FUNCTIONS-END

function [words, t0, t1] = transcribe_words(x, Fs, model, whisper_size, chunk_sec, pad_sec, cache_file)
    stt_fs = 16000;
    if Fs ~= stt_fs
        fprintf('Resampling to %d Hz for speech-to-text...\n', stt_fs);
        x16 = resample(x, stt_fs, Fs);
    else
        x16 = x(:);
    end
    total_sec  = numel(x16) / stt_fs;
    num_chunks = ceil(total_sec / chunk_sec);
    sig_id     = [numel(x16), sum(abs(x16(1:997:end)))];
    model_name = char(model);
    words = strings(0,1);  t0 = zeros(0,1);  t1 = zeros(0,1);
    first_chunk = 1;
    if isfile(cache_file)
        C = load(cache_file);
        if isfield(C,'sig_id') && isfield(C,'model_name') && isfield(C,'last_chunk') ...
                && isequal(C.sig_id, sig_id) && strcmp(C.model_name, model_name)
            words = C.words;  t0 = C.t0;  t1 = C.t1;
            first_chunk = C.last_chunk + 1;
            fprintf('Cache found - resuming at chunk %d of %d\n', first_chunk, num_chunks);
        end
    end
    if first_chunk <= num_chunks
        if strcmpi(model_name, 'whisper')
            client = speechClient("whisper", ModelSize=whisper_size, TimeStamps=true);
        else
            client = speechClient("wav2vec2.0", TimeStamps=true);
        end
    end
    for c = first_chunk:num_chunks
        own0 = (c-1) * chunk_sec;
        own1 = min(c * chunk_sec, total_sec);
        a  = max(0, own0 - pad_sec);
        b  = min(total_sec, own1 + pad_sec);
        i0 = floor(a * stt_fs) + 1;
        i1 = min(numel(x16), floor(b * stt_fs));
        seg = x16(i0:i1);
        try
            tbl = speech2text(seg, stt_fs, Client=client);
        catch ME
            if c == first_chunk, rethrow(ME); end
            warning('Chunk %d skipped: %s', c, ME.message);
            continue
        end
        [w, s0, s1] = parse_transcript(tbl);
        s0 = s0 + (i0-1)/stt_fs;
        s1 = s1 + (i0-1)/stt_fs;
        keep = s0 >= own0 & s0 < own1;
        words = [words; w(keep)];
        t0    = [t0; s0(keep)];
        t1    = [t1; s1(keep)];
        last_chunk = c;
        save(cache_file, 'sig_id', 'model_name', 'words', 't0', 't1', 'last_chunk');
        fprintf('  chunk %d/%d done (%d words so far)\n', c, num_chunks, numel(words));
    end
end

function [w, s0, s1] = parse_transcript(tbl)
    w = strings(0,1);  s0 = zeros(0,1);  s1 = zeros(0,1);
    if isempty(tbl), return; end
    if isstring(tbl) && all(strlength(tbl) == 0), return; end
    if ~istable(tbl)
        error('speech2text returned a %s, expected a table. The client needs TimeStamps=true.', class(tbl));
    end
    vn = tbl.Properties.VariableNames;
    lv = lower(vn);
    iw = find(contains(lv,'transcript') | contains(lv,'word') | contains(lv,'text'), 1);
    if isempty(iw), iw = 1; end
    it = find(contains(lv,'time'), 1);
    if isempty(it)
        disp(tbl(1:min(5,height(tbl)), :));
        error('No timestamp column in the transcript table. Variables found: %s', strjoin(vn, ', '));
    end
    w = string(tbl.(vn{iw}));  w = w(:);
    T = tbl.(vn{it});
    if iscell(T),     T = vertcat(T{:}); end
    if isduration(T), T = seconds(T);    end
    T = double(T);
    s0 = T(:,1);
    if size(T,2) >= 2
        s1 = T(:,2);
    else
        s1 = [s0(2:end); s0(end) + 0.3];
    end
end

function idx = find_keyword(words, kw_text)
    w   = lower(regexprep(string(words), '[^A-Za-z0-9]', ''));
    kws = lower(regexprep(split(string(strtrim(kw_text))), '[^A-Za-z0-9]', ''));
    kws = kws(strlength(kws) > 0);
    hit = false(size(w));
    for q = 1:numel(kws)
        hit = hit | contains(w, kws(q));
    end
    if ~any(hit)
        for q = 1:numel(kws)
            k = char(kws(q));
            max_ed = floor(0.3 * numel(k));
            if max_ed >= 1
                cand = find(abs(strlength(w) - numel(k)) <= max_ed);
                for c = cand(:)'
                    if lev(char(w(c)), k) <= max_ed
                        hit(c) = true;
                    end
                end
            end
        end
    end
    idx = find(hit);
end

function d = lev(a, b)
    m = numel(a);  n = numel(b);
    prev = 0:n;
    for i = 1:m
        cur = [i, zeros(1, n)];
        for j = 1:n
            cost = double(a(i) ~= b(j));
            cur(j+1) = min([prev(j+1) + 1, cur(j) + 1, prev(j) + cost]);
        end
        prev = cur;
    end
    d = prev(n+1);
end

