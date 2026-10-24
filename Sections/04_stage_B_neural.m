%% ============================================================
% 4. STAGE B: SPEECH-SPECIFIC NEURAL ENHANCEMENT
% (NEURAL_LOW_MIX, NEURAL_HIGH_MIX, NEURAL_SPLIT_HZ, NEURAL_CHUNK_SEC, NEURAL_OVERLAP_SEC)
% ============================================================

nn_ok = false;

% safe defaults, only used if 00_before_section_1.m did not define them
if ~exist('NEURAL_LOW_MIX',      'var'), NEURAL_LOW_MIX      = 0.90; end
if ~exist('NEURAL_HIGH_MIX',     'var'), NEURAL_HIGH_MIX     = 0.45; end
if ~exist('NEURAL_SPLIT_HZ',     'var'), NEURAL_SPLIT_HZ     = 1800; end
if ~exist('NEURAL_CHUNK_SEC',    'var'), NEURAL_CHUNK_SEC    = 20;   end
if ~exist('NEURAL_OVERLAP_SEC',  'var'), NEURAL_OVERLAP_SEC  = 1;    end

if USE_NEURAL_DENOISE
    disp(' ');
    disp('--- STAGE B: speech-specific enhancement ---');

    original_wiener = double(enhanced(:));
    N = numel(original_wiener);

    chunk_sec   = NEURAL_CHUNK_SEC;
    overlap_sec = NEURAL_OVERLAP_SEC;

    C = round(chunk_sec * Fs);
    O = round(overlap_sec * Fs);

    output_audio = zeros(N, 1);
    weight_sum   = zeros(N, 1);

    s = 1;
    chunk_number = 0;

    try
        while s <= N
            e = min(s + C - 1, N);

            input_chunk = single(original_wiener(s:e));

            % Neural speech enhancement
            enhanced_chunk = enhanceSpeech(input_chunk, Fs);
            enhanced_chunk = double(enhanced_chunk(:));

            % Ensure the output length matches the input length
            enhanced_chunk = fit_len( ...
                enhanced_chunk, e - s + 1);

            L = numel(enhanced_chunk);
            w = ones(L, 1);

            % Smooth crossfade between adjacent chunks
            % (half-sample offset so the two fades add up to exactly 1 and
            %  no single sample ever gets weight 0)
            if s > 1
                fade_len = min(O, L);
                w(1:fade_len) = ...
                    ((0:fade_len-1)' + 0.5) / fade_len;
            end

            if e < N
                fade_len = min(O, L);
                w(end-fade_len+1:end) = ...
                    1 - ((0:fade_len-1)' + 0.5) / fade_len;
            end

            output_audio(s:e) = output_audio(s:e) ...
                + enhanced_chunk .* w;

            weight_sum(s:e) = weight_sum(s:e) + w;

            chunk_number = chunk_number + 1;
            fprintf('  Enhanced chunk %d | %d-%d samples\n', ...
                chunk_number, s, e);

            if e >= N
                break;
            end

            s = e - O + 1;
        end

        valid = weight_sum > eps;
        output_audio(valid) = ...
            output_audio(valid) ./ weight_sum(valid);

        % Frequency-dependent blend:
        %  below the split  = where the cooler/fan noise lives -> mostly neural
        %  above the split  = consonants and brightness        -> mostly natural Wiener detail
        split_hz = NEURAL_SPLIT_HZ;

        [b, a] = butter(4, split_hz/(Fs/2), 'low');

        % Split Wiener-filtered audio
        low_wiener  = filtfilt(b, a, original_wiener);
        high_wiener = original_wiener - low_wiener;

        % Split neural-enhanced audio
        low_neural  = filtfilt(b, a, output_audio);
        high_neural = output_audio - low_neural;

        % Independent mixing strengths
        low_neural_mix  = NEURAL_LOW_MIX;
        high_neural_mix = NEURAL_HIGH_MIX;

        % Blend each frequency region separately
        enhanced = ...
            (1 - low_neural_mix)  * low_wiener  + ...
            low_neural_mix        * low_neural  + ...
            (1 - high_neural_mix) * high_wiener + ...
            high_neural_mix       * high_neural;

        % Prevent clipping
        enhanced = enhanced / (max(abs(enhanced)) + eps);

        nn_ok = true;
        disp('  Speech-specific neural enhancement completed.');

    catch ME
        enhanced = original_wiener;

        warning('Speech enhancement could not run: %s', ...
            ME.message);

        disp('  Keeping the existing Wiener-filtered audio.');
    end
end
%% ---- VOICE RESTORE: puts back the voice peaks the neural mask cut ----
if ~exist('RS_PEAK_DB', 'var'),  RS_PEAK_DB  = 8;  end   % peak above local floor (6 = more voice)
if ~exist('RS_NOISE_DB','var'),  RS_NOISE_DB = 14; end   % peak above bin noise floor (16-18 if noise returns)
if ~exist('RS_FLOOR','var'), RS_FLOOR = 0.20; end   % 0.12 = cleaner, 0.30 = fuller voice
if nn_ok
    rs_N = 512;  rs_H = 256;  rs_h = rs_N/2 + 1;
    rs_w = single(sqrt(0.5*(1 - cos(2*pi*(0:rs_N-1)'/rs_N))));
    rs_L = numel(enhanced);
    rs_nF = ceil((rs_L + rs_N)/rs_H) + 1;
    rs_T  = (rs_nF-1)*rs_H + rs_N;
    rs_x  = single([zeros(rs_N,1); original_wiener(:); zeros(rs_T-rs_N-rs_L,1)]);
    rs_e  = single([zeros(rs_N,1); enhanced(:);        zeros(rs_T-rs_N-rs_L,1)]);
    rs_i  = (1:rs_N)' + rs_H*(0:rs_nF-1);
    rs_W  = fft(rs_x(rs_i) .* rs_w);  rs_W = rs_W(1:rs_h,:);
    rs_E  = fft(rs_e(rs_i) .* rs_w);  rs_E = rs_E(1:rs_h,:);

    rs_P  = abs(rs_W).^2 + 1e-12;
    rs_LG = log(rs_P);
    rs_ps = sort(rs_P, 2);
    rs_NB = rs_ps(:, max(1, round(0.2*rs_nF)));  clear rs_ps       % noise floor of each bin
        rs_b1 = ceil(100/(Fs/rs_N)) + 1;  rs_b2 = floor(1499/(Fs/rs_N)) + 1;
    rs_K  = (rs_LG > movmean(rs_LG, 15, 1) + RS_PEAK_DB*log(10)/10) ...
          & (rs_P > 10^(RS_NOISE_DB/10) .* rs_NB);
    rs_K(1:floor(100/(Fs/rs_N)), :) = false;
    rs_EA = sum(abs(rs_E).^2, 1);
    rs_K  = rs_K & (rs_EA > 1e-4*max(rs_EA));                          % stricter: only real speech frames
    rs_K  = rs_K & (conv2(single(rs_K), [1 0 1; 1 0 1; 1 0 1], 'same') > 0);  % must continue in time -> no chirps
    rs_K  = movmax(single(rs_K), 3, 1);
    rs_voiced = sum(rs_K(rs_b1:rs_b2, :), 1) >= 9;                     % voiced frame = many harmonic peaks
    rs_K  = rs_K .* rs_voiced;
    rs_K  = rs_K .* sqrt(max(1 - 4.5*rs_NB ./ rs_P, 0));
    rs_M  = max(min(1, abs(rs_E)./sqrt(rs_P)), rs_K);
    rs_v  = movmax(single(rs_voiced), 5, 2);                           % valley floor: no deep holes between harmonics
    rs_M  = max(rs_M, RS_FLOOR * single((0:rs_h-1)'*Fs/rs_N < 5000) .* rs_v);
    rs_M  = movmean(movmean(rs_M, 3, 1), 3, 2);

    rs_y  = real(ifft([rs_W.*rs_M; conj(rs_W(end-1:-1:2,:).*rs_M(end-1:-1:2,:))])) .* rs_w;
    rs_o  = accumarray(rs_i(:), double(rs_y(:)), [rs_T 1]);
    rs_o  = rs_o(rs_N+1 : rs_N+rs_L);
    enhanced = rs_o / (max(abs(rs_o)) + eps);
    clear rs_*
end

%% ---- AUTOMATIC SPECTRAL BALANCE (fixes dull / honky / thin voice) ----
% Measures the average spectrum of the professor's speech and gently reshapes it
% toward a natural male-speech curve (limited boost/cut, linear-phase, no ringing).
if ~exist('AUTO_TONE_MATCH',  'var'), AUTO_TONE_MATCH  = true; end
if ~exist('TONE_MAX_BOOST_DB','var'), TONE_MAX_BOOST_DB = 10;  end
if ~exist('TONE_MAX_CUT_DB',  'var'), TONE_MAX_CUT_DB   = 8;   end
if ~exist('TONE_AMOUNT',      'var'), TONE_AMOUNT       = 1.0; end

if AUTO_TONE_MATCH
    disp('  Auto spectral balance (restoring natural voice tone)...');
    tm_x   = double(enhanced(:));
    tm_hop = round(0.02 * Fs);
    tm_nb  = floor(numel(tm_x) / tm_hop);
    tm_fr  = reshape(tm_x(1:tm_nb*tm_hop), tm_hop, tm_nb);
    tm_lv  = 10*log10(mean(tm_fr.^2, 1) + 1e-12);
    tm_s   = sort(tm_lv);
    tm_thr = tm_s(max(1, round(0.60 * tm_nb)));
    tm_idx = find(tm_lv > tm_thr);
    tm_idx = tm_idx(1:3:end);

    tm_nfft = 2048;
    if numel(tm_idx) * tm_hop >= 4 * tm_nfft
        tm_xs  = reshape(tm_fr(:, tm_idx), [], 1);
        tm_win = 0.5 * (1 - cos(2*pi*(0:tm_nfft-1)' / tm_nfft));
        tm_nseg = floor((numel(tm_xs) - tm_nfft) / (tm_nfft/2)) + 1;
        tm_P = zeros(tm_nfft/2 + 1, 1);
        for tm_k = 1:tm_nseg
            tm_s0 = (tm_k-1) * (tm_nfft/2) + 1;
            tm_X  = fft(tm_xs(tm_s0:tm_s0+tm_nfft-1) .* tm_win);
            tm_P  = tm_P + abs(tm_X(1:tm_nfft/2+1)).^2;
        end
        tm_f = (0:tm_nfft/2)' * Fs / tm_nfft;

        % 1/3-octave bands (centre frequencies) and the target speech curve (dB)
        tm_fc = 125 * 2.^((0:17)/3);
        tm_T  = [-3 -1.5 0 1 1 0.5 0 -1.5 -3.5 -5.5 -7.5 -9.5 -11.5 -13.5 -15.5 -17.5 -20 -23];
        tm_ok = tm_fc * 2^(1/6) < Fs/2;
        tm_fc = tm_fc(tm_ok);
        tm_T  = tm_T(tm_ok);
        tm_nbnd = numel(tm_fc);

        tm_L = zeros(1, tm_nbnd);
        for tm_q = 1:tm_nbnd
            tm_sel = tm_f >= tm_fc(tm_q)/2^(1/6) & tm_f < tm_fc(tm_q)*2^(1/6);
            tm_L(tm_q) = 10*log10(sum(tm_P(tm_sel)) + 1e-20);
        end

        tm_D   = tm_T - tm_L;                                   % what each band is missing
        tm_mid = tm_fc >= 200 & tm_fc <= 4000;
        tm_C   = tm_D - median(tm_D(tm_mid));                   % keep overall level, fix only the SHAPE
        tm_C(tm_fc < 400) = min(tm_C(tm_fc < 400), 6);          % never over-boost the low end (cooler lives there)
        tm_C   = min(max(tm_C, -TONE_MAX_CUT_DB), TONE_MAX_BOOST_DB);
        tm_C   = movmean(tm_C, 3, 'Endpoints', 'shrink');       % smooth curve
        tm_C   = TONE_AMOUNT * tm_C;

        fprintf('  correction (dB) at Hz: ');
        for tm_q = 1:tm_nbnd
            fprintf('%d:%+.1f  ', round(tm_fc(tm_q)), tm_C(tm_q));
        end
        fprintf('\n');

        % linear-phase FIR (zero net delay)
        tm_F = [0, 60, tm_fc, Fs/2] / (Fs/2);
        tm_A = 10 .^ ([0, 0, tm_C, tm_C(end)] / 20);
        tm_b = fir2(1024, tm_F, tm_A);
        tm_d = 512;
        tm_y = fftfilt(tm_b, [tm_x; zeros(tm_d, 1)]);
        enhanced = tm_y(tm_d+1 : tm_d+numel(tm_x));
        enhanced = enhanced / (max(abs(enhanced)) + eps);
    else
        disp('  (not enough speech found for spectral balance - skipped)');
    end
    clear tm_*
end
