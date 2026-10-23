%% ============================================================
% 6. STAGE D: VOICE GATE (professor only)
% ============================================================
disp(' ');
disp('--- STAGE D: voice gate (keeps only the professor) ---');
if VG.enable
    [gate, enhanced] = voice_gate(enhanced, Fs, hop_size, VG);
else
    gate = ones(ceil(numel(enhanced)/hop_size), 1);
end
is_speech = gate > 0.5;
fprintf('  Professor speaking : %.1f%% of the recording\n', 100*mean(is_speech));
fprintf('  Everything else    : cut by up to %d dB\n', abs(VG.pause_db));
enhanced = enhanced / (max(abs(enhanced)) + eps);
