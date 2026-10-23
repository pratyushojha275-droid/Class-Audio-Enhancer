%% ============================================================
% 10. EVALUATION, PLOTS, AND QUALITY REPORT
% ============================================================
disp(' ');
disp('--- GENERATING QUALITY REPORT ---');
N     = length(original_audio);
N_enh = length(enhanced);
step  = max(1, floor(N/50000));
nfft  = 4096;

[P_orig, f] = pwelch(original_audio, hamming(nfft), nfft/2, nfft, Fs);
[P_enh,  ~] = pwelch(enhanced,       hamming(nfft), nfft/2, nfft, Fs);

fig1 = figure('Name','DSP Project Evaluation', 'Position',[100 100 1000 800]);

subplot(2,2,1);
plot((0:step:N-1)/Fs, original_audio(1:step:end), 'r');
title('Original Waveform'); xlabel('Time (s)'); ylabel('Amplitude'); grid on;

subplot(2,2,2);
plot((0:step:N_enh-1)/Fs, enhanced(1:step:end), 'b');
title('Enhanced + Leveled Waveform'); xlabel('Time (s)'); ylabel('Amplitude'); grid on;

subplot(2,2,3);
plot(f, 10*log10(P_orig + eps), 'r');
title('Original Spectrum'); xlabel('Frequency (Hz)'); ylabel('Power/Hz (dB)'); xlim([0 Fs/2]); grid on;

subplot(2,2,4);
plot(f, 10*log10(P_enh + eps), 'b');
title('Enhanced Spectrum'); xlabel('Frequency (Hz)'); ylabel('Power/Hz (dB)'); xlim([0 Fs/2]); grid on;

saveas(fig1, fullfile(OUTPUT_DIR, '06_dsp_evaluation_plots.png'));

lvl_o   = block_levels_db(original_audio, hop_size);
lvl_e   = block_levels_db(enhanced,       hop_size);
sp_eval = double(is_speech(1:min(numel(lvl_o), numel(is_speech))));
sp_eval(end+1:numel(lvl_o)) = sp_eval(end);
W_eval  = max(3, round(1.0 * Fs / hop_size));
curve_o = speech_level_curve(lvl_o, sp_eval, W_eval);
curve_e = speech_level_curve(lvl_e, sp_eval, W_eval);
[LU_o, LU_unit] = measure_lufs(original_audio, Fs);
[LU_e, ~]       = measure_lufs(enhanced,       Fs);

fig2 = figure('Name','Loudness Consistency', 'Position',[150 150 1000 350]);
t_min = ((0:numel(curve_o)-1)' * hop_size / Fs) / 60;
plot(t_min, curve_o, 'r'); hold on;
plot(t_min, curve_e, 'b'); hold off;
title('Speech loudness over time (flatter = more even)');
xlabel('Time (min)'); ylabel('Level (dB)'); legend('Original', 'Enhanced + Leveled'); grid on;
saveas(fig2, fullfile(OUTPUT_DIR, '07_loudness_plots.png'));

% how far the voice stands above the background, before vs after
sp_mask = sp_eval > 0.5;
if any(sp_mask)
    voice_o = median(lvl_o(sp_mask));
    voice_e = median(lvl_e(sp_mask(1:min(end,numel(lvl_e)))));
    bg_o    = pct_sorted(lvl_o, 5);
    bg_e    = pct_sorted(lvl_e, 5);
    gap_o   = voice_o - bg_o;
    gap_e   = voice_e - bg_e;
else
    gap_o = NaN;  gap_e = NaN;
end

fprintf('\n============================================\n');
fprintf('             PROJECT QUALITY REPORT\n');
fprintf('============================================\n');
fprintf('Noise level  : %d (1 gentle / 2 strong / 3 maximum)\n', NOISE_LEVEL);
fprintf('Pre-filter   : %d Hz high-pass (order %d) + %d detected hum/buzz notches\n', HP_CUTOFF, HP_ORDER, numel(tones));
fprintf('Neural stage : %s\n', ternary(nn_ok, sprintf('used (%d pass(es))', NEURAL_PASSES), 'not used'));
fprintf('Voice gate   : professor speaking %.1f%% of the recording\n', 100*mean(is_speech));
fprintf('Voice vs background gap : original %.1f dB -> enhanced %.1f dB\n', gap_o, gap_e);
fprintf('Loudness     : original %.1f %s -> enhanced %.1f %s\n', LU_o, LU_unit, LU_e, LU_unit);
fprintf('Long pauses removed (Smart Revision): %d\n', pauses_removed);
fprintf('ALL OUTPUT FILES SAVED IN: %s\n', OUTPUT_DIR);
fprintf('============================================\n');
disp('PROCESS COMPLETED SUCCESSFULLY.');

if ispc
    winopen(OUTPUT_DIR);
end
