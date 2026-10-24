%% ============================================================
% 2. PRE-FILTER
% High-pass filter + conservative automatic hum/buzz notches
%% ============================================================

disp('Designing conservative pre-filter...');

tones = [];

if AUTO_NOTCH

    % Restrict the search to prominent low-frequency tones.
    % Previous configuration searched up to 2500 Hz and selected
    % 10 peaks, which could interfere with important speech bands.

    tones = detect_tones( ...
        audio, Fs, TONE_MIN_DB, 90, 250, TONE_MAX_N);

    fprintf('Auto-detected %d low-frequency tones (Hz): %s\n', ...
        numel(tones), mat2str(round(tones, 1)));

else

    % Do not insert arbitrary fixed-frequency notches.
    tones = [];
end

%% ---- HIGH-PASS FILTER ----------------------------------------

[zz, pp, kk] = butter( ...
    HP_ORDER, HP_CUTOFF/(Fs/2), 'high');

[sos_all, g_all] = zp2sos(zz, pp, kk);

%% ---- APPLY NARROW NOTCH FILTERS -------------------------------

for i = 1:numel(tones)

    % Ignore invalid frequencies.
    if tones(i) <= 0 || tones(i) >= Fs/2
        continue;
    end

    w0 = tones(i)/(Fs/2);

    [b_n, a_n] = iirnotch( ...
        w0, w0/NOTCH_Q);

    sos_all = [sos_all; [b_n, a_n]];
end

%% ---- FILTER THE INPUT AUDIO -----------------------------------

fprintf('Applying %d Hz high-pass (order %d) and %d notches...\n', ...
    HP_CUTOFF, HP_ORDER, numel(tones));

cleaned_initial = filtfilt(sos_all, g_all, audio);

clear audio;

disp('Pre-filter completed.');
