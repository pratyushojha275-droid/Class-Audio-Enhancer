%% CLASS AUDIO ENHANCER V4 - MASTER RUNNER
% This script combines all 13 section files and runs the full program.
% Run this file only.

clc;

% Find the folder containing this script.
projectFolder = fileparts(mfilename('fullpath'));

if isempty(projectFolder)
    projectFolder = pwd;
end

% List all source sections in their required execution order.
sectionFiles = {
    '00_before_section_1.m'
    '01_pre_processing.m'
    '02_pre_filter.m'
    '03_stage_A_wiener.m'
    '04_stage_B_neural.m'
    '05_stage_C_polish.m'
    '06_stage_D_voice_gate.m'
    '07_clarity_EQ_leveling.m'
    '08_transcription_topic_extraction.m'
    '09_smart_revision.m'
    '10_evaluation_report.m'
    '11_text_to_audio.m'
    'Local_functions.m'
};

% Verify that every section exists.
for k = 1:numel(sectionFiles)
    sectionPath = fullfile(projectFolder, sectionFiles{k});

    if ~isfile(sectionPath)
        error('Missing section file: %s', sectionFiles{k});
    end
end

% Build the complete script in the same order.
combinedPath = fullfile( ...
    projectFolder, 'class_audio_enhancer_v4_combined.m');

fid = fopen(combinedPath, 'w');

if fid == -1
    error('Cannot create the combined MATLAB file.');
end

try
    for k = 1:numel(sectionFiles)
        sectionPath = fullfile(projectFolder, sectionFiles{k});
        sectionCode = fileread(sectionPath);

        fprintf(fid, ...
            '%% ===== BEGIN %s =====\n\n', sectionFiles{k});

        fprintf(fid, '%s\n\n', sectionCode);

        fprintf(fid, ...
            '%% ===== END %s =====\n\n', sectionFiles{k});
    end

    fclose(fid);

catch ME
    fclose(fid);
    rethrow(ME);
end

fprintf('Combined MATLAB script created successfully.\n');
fprintf('Running: %s\n\n', combinedPath);

% Execute the complete program.
run(combinedPath);  
