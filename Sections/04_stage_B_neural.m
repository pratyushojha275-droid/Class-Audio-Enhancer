%% ============================================================
% 4. STAGE B: NEURAL DENOISER (on top of the Wiener result)
% ============================================================
nn_ok = false;
if USE_NEURAL_DENOISE
    disp(' ');
    disp('--- STAGE B: neural denoiser (denoiseNet) ---');
    [enhanced, nn_ok] = neural_denoise(enhanced, Fs, NEURAL_PASSES, NEURAL_MIX, ...
                                       NEURAL_CHUNK_SEC, NEURAL_OVERLAP_SEC);
    if ~nn_ok
        disp('  Neural denoiser NOT available -> an extra classical cleaning pass will be used instead.');
        disp('  (To enable it: MATLAB Home > Add-Ons > Get Add-Ons, search "Audio Toolbox" / "Deep Learning Toolbox" / "denoiseNet".)');
    end
end
