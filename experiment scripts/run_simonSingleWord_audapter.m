function [expt] = run_simonSingleWord_audapter(expt, conds2run)
% Companion function of run_simonSingleWord_expt. Shows words on screen,
%   records audio with Audapter, then perturbs vowels as per
%   expt.shiftAngles and expt.shiftMags.

if nargin < 1, error('Need expt file to run this function'); end
if nargin < 2, conds2run = expt.conds; end

trialdirname = 'temp_trials';
outputdir = expt.dataPath;
trialdir = fullfile(outputdir, trialdirname);
if ~exist(trialdir, 'dir')
    mkdir(trialdir)
end

rmsThresh = 0.04;   %threshold for bGoodTrial
stimtxtsize = 200;

expt = set_exptDefaults(expt);
save(fullfile(outputdir,'expt.mat'), 'expt');

if ~expt.isRestart
    firstTrial = find(expt.allConds == find(strcmp(expt.conds, conds2run{1})),   1, 'first');
    lastTrial  = find(expt.allConds == find(strcmp(expt.conds, conds2run{end})), 1, 'last');
else
    firstTrial = expt.startTrial;
    lastTrial = expt.ntrials;
end

%% setup for audapter

helpersDir = fullfile(get_gitPath('current-studies'), 'simonSingleWord');

ostFN = fullfile(helpersDir, 'bedheadWorking.ost');
pcfFN = fullfile(helpersDir, 'bedheadWorking.pcf');
check_file(ostFN);
check_file(pcfFN);
Audapter('ost', ostFN, 0);
Audapter('pcf', pcfFN, 0);

audioInterfaceName = 'Focusrite USB';
sRate = 48000;
downFact = 3;
frameLen = 96/downFact;

Audapter('deviceName', audioInterfaceName);
Audapter('setParam', 'sRate', sRate / downFact, 0);
Audapter('setParam', 'downFact', downFact, 0);
Audapter('setParam', 'frameLen', frameLen, 0);

p = getAudapterDefaultParams(expt.gender);

if isfield(expt, 'audapterParams')
    p = add2struct(p, expt.audapterParams);
end
p.bPitchShift = 0;
p.downFact = downFact;
p.sr = sRate / downFact;
p.frameLen = frameLen;
p.bShift = 1;
p.bRatioShift = 0;
p.bMelShift = 1;

w = get_noiseSource(p);
Audapter('setParam', 'datapb', w, 1);
p.fb = 3;
p.fb3Gain = 0.02;

expt.audapterParams = p;

%% initialize Audapter
AudapterIO('init', p);

%% run experiment

h_fig = setup_exptFigs;
get_figinds_audapter;
h_sub = get_subfigs_audapter(h_fig(ctrl),1);

add_adjustOstButton(h_fig);

h_ready = draw_exptText(h_fig,.5,.5, expt.instruct.introtxt, expt.instruct.txtparams);
pause
delete_exptText(h_fig,h_ready)

pause(1)

for itrial = firstTrial:lastTrial
    bGoodTrial = 0;
    while ~bGoodTrial
        if get_pause_state(h_fig,'p')
            pause_trial(h_fig);
        end
        if get_pause_state(h_fig,'a') % Pause for adjusting OSTs
            adjustOsts(expt, h_fig);
        end
        
        cla(h_sub(1))
        ctrltxt = sprintf('trial: %d/%d, cond: %s',itrial,expt.ntrials,expt.listConds{itrial});
        h_trialn = text(h_sub(1),0,0.5,ctrltxt,'Color','black', 'FontSize',30, 'HorizontalAlignment','center'); %#ok<NASGU> % don't delete this
        
        txt2display = expt.listStimulusText{itrial};
        color2display = expt.colorvals{expt.allColors(itrial)};
        
        % change the phi and mag values
        for i = 0:3
            set_pcf('simonSingleWord', 'bedhead', 'space', i, 'fmtPertPhi', expt.shiftAngles(1));
        end
        for i = 4:8
            set_pcf('simonSingleWord', 'bedhead', 'space', i, 'fmtPertPhi', expt.shiftAngles(2));
        end
        for i = 0:8
            set_pcf('simonSingleWord', 'bedhead', 'space', i, 'fmtPertAmp', expt.shiftMags(itrial));
        end
        Audapter('pcf',pcfFN,0) % send new values to Audapter
        
        Audapter('reset');
        fprintf('starting trial %d\n',itrial)
        Audapter('start');
        
        fprintf('Audapter started for trial %d\n',itrial)
        
        h_text(1) = draw_exptText(h_fig,.5,.5,txt2display, 'Color',color2display, 'FontSize',stimtxtsize, 'HorizontalAlignment','center');
        
        pause(expt.timing.stimdur);
        
        Audapter('stop');
        fprintf('Audapter ended for trial %d\n',itrial)
        
        data = AudapterIO('getData');
        
        % plot shifted spectrogram
        subplot_expt_spectrogram(data, p, h_fig, h_sub)
        % get info for trial-specific OSTs
        subjOstParams = get_ost(expt.trackingFileLoc, expt.trackingFileName, 'full', 'working'); 
        data.subjOstParams = subjOstParams; 
        data.bChangeOst = 0; 
        
        bGoodTrial = check_rmsThresh(data, rmsThresh, h_sub(3));
        %bGoodTrial = 1; %Use if testing without being able to record
        
        delete_exptText(h_fig,h_text)
        clear h_text
        
        if ~bGoodTrial
            h_text = draw_exptText(h_fig,.5,.2,'Please speak a little louder','FontSize',40,'HorizontalAlignment','center','Color','y');
            pause(1)
            delete_exptText(h_fig,h_text)
            clear h_text
        end
        
        pause(expt.timing.interstimdur + rand * expt.timing.interstimjitter);
        
        trialfile = fullfile(trialdir, sprintf('%d.mat',itrial));
        save(trialfile,'data')
        
        clear data
    end
    
    % Break trials and end-of-experiment screens
    if itrial == expt.ntrials
        breaktext = sprintf('Thank you!\n\nPlease wait.');
        draw_exptText(h_fig,.5,.5,breaktext,expt.instruct.txtparams);
        pause(3);
    elseif any(expt.breakTrials == itrial)
        breaktext = sprintf('Time for a break!\n%d of %d trials done.\n\nPress the space bar to continue.',itrial,expt.ntrials);
        h_break = draw_exptText(h_fig,.5,.5,breaktext,expt.instruct.txtparams);
        pause
        delete_exptText(h_fig,h_break)
    end
    
end

%% compile trials into data.mat. Save metadata.
if any(ismember(conds2run, expt.conds{end}))
    alldata = struct;
    fprintf('Processing data\n')
    for i = 1:expt.ntrials
        trialfile = fullfile(trialdir,sprintf('%d.mat',i));
        if exist(trialfile,'file')
            load(trialfile,'data')
            names = fieldnames(data);
            for j = 1:length(names)
                alldata(i).(names{j}) = data.(names{j});
            end
        else
            warning('Trial %d not found.',i)
        end
    end
    
    fprintf('Saving data... ')
    clear data
    data = alldata;
    save(fullfile(outputdir,'data.mat'), 'data')
    fprintf('saved.\n')
    
    fprintf('Saving expt... ')
    save(fullfile(outputdir,'expt.mat'), 'expt')
    fprintf('saved.\n')
    
    fprintf('Removing temp directory... ')
    rmdir(trialdir,'s');
    fprintf('done.\n')
    
end

%% close figures
close(h_fig)


end %EOF