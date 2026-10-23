%% ============================================================
% 9. SMART REVISION MODE
%    Long pauses are shortened (a little room tone is kept on each side
%    of the cut and the joins are faded, so there are no clicks).
% ============================================================
disp(' ');
disp('--- MODULE 4: SMART REVISION ---');
pause_threshold = 1.5;
short_pause     = 0.3;

mask  = repelem(is_speech(:), hop_size);
mask  = mask(1:length(enhanced));

d       = diff([0; double(~mask); 0]);
p_start = find(d == 1);
p_end   = find(d == -1) - 1;
p_len   = (p_end - p_start + 1) / Fs;
long_idx = find(p_len >= pause_threshold);
pauses_removed = numel(long_idx);

keep    = round(short_pause/2 * Fs);
F       = round(0.015 * Fs);
fade_in = 0.5 * (1 - cos(pi*(0:F-1)'/(F-1)));

n_pieces  = pauses_removed + 1;
seg_start = ones(n_pieces, 1);
seg_stop  = repmat(length(enhanced), n_pieces, 1);
for j = 1:pauses_removed
    q = long_idx(j);
    seg_stop(j)    = p_start(q) + keep - 1;
    seg_start(j+1) = p_end(q)   - keep + 1;
end

pieces = cell(n_pieces, 1);
for j = 1:n_pieces
    seg = enhanced(seg_start(j):seg_stop(j));
    if j > 1,        seg(1:F)         = seg(1:F)         .* fade_in;        end
    if j < n_pieces, seg(end-F+1:end) = seg(end-F+1:end) .* flipud(fade_in); end
    pieces{j} = seg;
end

revision_audio = vertcat(pieces{:});
audiowrite(fullfile(OUTPUT_DIR, '05_smart_revision.wav'), revision_audio, Fs);
disp('Smart revision complete. Saved into dsp_project folder.');

