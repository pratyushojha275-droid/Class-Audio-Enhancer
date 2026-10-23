%% ============================================================
% CLASS AUDIO ENHANCER V4 - MASTER RUNNER
% Run this file only.
%
% Includes every section file, including:
% 08_transcription_topic_extraction.m
%
% Preserves the existing project structure.
%% ============================================================

clc;

%% ---- STEP 1: FIND PROJECT FOLDER -----------------------------

projectFolder = fileparts(mfilename('fullpath'));

if isempty(projectFolder)
    projectFolder = pwd;
end

cd(projectFolder);

fprintf('\n============================================\n');
fprintf('CLASS AUDIO ENHANCER V4\n');
fprintf('============================================\n');

fprintf('Project folder:\n%s\n', projectFolder);

%% ---- STEP 2: ADD PROJECT FOLDERS TO MATLAB PATH ---------------

addpath(genpath(projectFolder));

fprintf('\nProject folders added to MATLAB path.\n');

%% ---- STEP 3: ADD DOWNLOADED WHISPER MODEL TO PATH --------------

desktopPath = fullfile(getenv('USERPROFILE'), 'Desktop');
dspOutputFolder = fullfile(desktopPath, 'dsp_project');

modelDirs = {
    fullfile(dspOutputFolder, 'whisper-base.en-model')
    fullfile(dspOutputFolder, 'whisper-base-model')
};

modelFound = false;

for k = 1:numel(modelDirs)

    if isfolder(modelDirs{k})

        addpath(genpath(modelDirs{k}));

        fprintf('Whisper model folder added:\n%s\n', ...
            modelDirs{k});

        modelFound = true;
    end
end

if ~modelFound
    warning(['No extracted Whisper model folder was found. ', ...
        'Speech-to-text may fail if model files are unavailable.']);
end

%% ---- STEP 4: LIST ALL SOURCE FILES IN EXECUTION ORDER ---------

% IMPORTANT:
% The section filename below matches your current filename exactly.
% Do not automatically rename it.

sectionFiles = {
    fullfile('before_section_1', '00_before_section_1.m')

    fullfile('sections', '01_pre_processing.m')
    fullfile('sections', '02_pre_filter.m')
    fullfile('sections', '03_stage_A_wiener.m')
    fullfile('sections', '04_stage_B_neural.m')
    fullfile('sections', '05_stage_C_polish.m')
    fullfile('sections', '06_stage_D_voice_gate.m')
    fullfile('sections', '07_clarity_EQ_leveling.m')

    fullfile('sections', '08_transcription_topic_extraction.m')

    fullfile('sections', '09_smart_revision.m')
    fullfile('sections', '10_evaluation_report.m')
    fullfile('sections', '11_text_to_audio.m')

    fullfile('functions', 'Local_functions.m')
};

%% ---- STEP 5: VERIFY ALL FILES EXIST ---------------------------

fprintf('\nChecking all source files...\n');

for k = 1:numel(sectionFiles)

    sectionPath = fullfile(projectFolder, sectionFiles{k});

    if ~isfile(sectionPath)
        error('Missing source file:\n%s', sectionPath);
    end

    fprintf('OK: %s\n', sectionFiles{k});
end

fprintf('\nAll %d source files were found.\n', numel(sectionFiles));

%% ---- STEP 6: CREATE COMBINED MATLAB SCRIPT --------------------

combinedPath = fullfile(projectFolder, ...
    'class_audio_enhancer_v4_combined.m');

fid = fopen(combinedPath, 'w');

if fid == -1
    error('Cannot create the combined MATLAB file:\n%s', combinedPath);
end

try

    for k = 1:numel(sectionFiles)

        sectionPath = fullfile(projectFolder, sectionFiles{k});
        sectionCode = fileread(sectionPath);

        fprintf(fid, '%% ===== BEGIN %s =====\n\n', ...
            sectionFiles{k});

        fprintf(fid, '%s\n\n', sectionCode);

        fprintf(fid, '%% ===== END %s =====\n\n', ...
            sectionFiles{k});

        % Set the intended Whisper model after the initial
        % configuration section has executed.
        if k == 1

            fprintf(fid, ...
                '%% ===== WHISPER CONFIGURATION =====\n');

            fprintf(fid, 'STT_MODEL = "whisper";\n');
            fprintf(fid, 'WHISPER_SIZE = "base";\n\n');

        end
    end

    fclose(fid);
    fid = -1;

catch ME

    if fid ~= -1
        fclose(fid);
    end

    rethrow(ME);

end

fprintf('\nCombined MATLAB script created successfully:\n');
fprintf('%s\n', combinedPath);

%% ---- STEP 7: RUN THE COMPLETE PROGRAM -------------------------

fprintf('\nStarting the complete audio enhancement pipeline...\n\n');

run(combinedPath);
