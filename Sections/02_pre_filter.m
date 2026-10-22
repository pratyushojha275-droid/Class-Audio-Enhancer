%% ============================================================
% 2. PRE-FILTER: steep high-pass + auto-detected hum/buzz notches
% ============================================================
disp('Designing pre-filter (steep high-pass + detected hum/buzz notches)...');

tones = [];
if AUTO_NOTCH
    tones = detect_tones(audio, Fs, TONE_MIN_DB, 90, 2500, TONE_MAX_N);
    fprintf('Auto-detected %d hum/buzz tones (Hz): %s\n', numel(tones), mat2str(round(tones,1)));
else
    tones = [50 100 150 200 250];
end

[zz, pp, kk] = butter(HP_ORDER, HP_CUTOFF/(Fs/2), 'high');
[sos_all, g_all] = zp2sos(zz, pp, kk);
for i = 1:numel(tones)
    w0 = tones(i) / (Fs/2);
    [b_n, a_n] = iirnotch(w0, w0 / NOTCH_Q);
    sos_all = [sos_all; [b_n, a_n]];
end

fprintf('Applying %d Hz high-pass (order %d) and %d notches...\n', HP_CUTOFF, HP_ORDER, numel(tones));
cleaned_initial = filtfilt(sos_all, g_all, audio);
clear audio;

