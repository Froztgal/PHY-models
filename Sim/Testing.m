% ����
clear; close all;
addpath('./Watermark/BCH1/mat');
addpath('./Watermark/matlab')

% ��������� ��� ������ ������ BCH1                               
% �������� ���������� �������������� BCH1 ������ �������
load BCH1_001.mat; 

% ��������� ��������� ������ �� ������ ����������� 5 ��� ��� BCH1    
QAM_ModulationOrder = 4; % QPSK ��� ������ ������.
Number_of_carriers = 250; % 250 - ����
NumberOfSymbolsInTime = 50; % 50
Subcarrier_Spacing = 20; %10, 5; 20 - ����
SamplingRate = Number_of_carriers*Subcarrier_Spacing*4;
dt = 1/SamplingRate;
% Simulation_SNR_dB = 0;
Simulation_SNR_dB = 0:5:50; % SNR for OFDM in dB. The average transmit power of all methods is the same! However, the SNR might be different due to filtering (in FOFDM and UFMC) or because a different bandwidth is used (different subcarrier spacing or different number of subcarriers).          
f_central = 35000;
pilot_sep_freq = 2;
pilot_sep_time = 1;

% Number of Monte Carlo repetitions over which we take the average
memory_X = {};
memory_Y = {};
memory_Y_eq = {};
Simulation_MonteCarloRepetitions = 5;                                  

% ��������� ����������� �������������� ����
% FBMC parameters
FBMC_NumberOfSubcarriers = Number_of_carriers;        
FBMC_NumberOfSymbolsInTime = NumberOfSymbolsInTime;                                    
FBMC_SubcarrierSpacing = Subcarrier_Spacing;                                   
FBMC_PrototypeFilter = 'Hermite-QAM'; % Prototype filter (Hermite, PHYDYAS, RRC) and OQAM or QAM.
FBMC_OverlappingFactor = 4; % Overlapping factor, 2,3,4,...

%% Generate " +Modulation\" Objects
% FBMC Object
FBMC = Modulation.FBMC(...
    FBMC_NumberOfSubcarriers,...                                        % Number of subcarriers
    FBMC_NumberOfSymbolsInTime,...                                      % Number FBMC symbols in time
    FBMC_SubcarrierSpacing,...                                          % Subcarrier spacing (Hz)
    SamplingRate,...                                                    % Sampling rate (Samples/s)
    0,...                                                               % Intermediate frequency of the first subcarrier (Hz).  Must be a multiple of the subcarrier spacing
    false,...                                                           % Transmit real valued signal (sampling theorem must be fulfilled!)
    FBMC_PrototypeFilter,...                                            % Prototype filter (Hermite, PHYDYAS, RRC) and OQAM or QAM. The data rate of QAM is reduced by a factor of two compared to OQAM, but robustness in doubly-selective channels is inceased
    FBMC_OverlappingFactor, ...                                         % Overlapping factor (also determines oversampling in the frequency domain)                                   
    0, ...                                                              % Initial phase shift
    true ...                                                            % Polyphase implementation
    );
FBMC_BlockOverlapTime = (FBMC.PrototypeFilter.OverlappingFactor-1/2)*FBMC.PHY.TimeSpacing;

% ���������� ������� 
ChannelEstimation = ChannelEstimation.PilotSymbolAidedChannelEstimation(...
    'Diamond',...                                                       % Pilot pattern, 'Diamond','Rectangular', 'Custom'
    [...                                                                % Matrix that represents the pilot pattern parameters
    Number_of_carriers,...                                                 % Number of subcarriers
    pilot_sep_freq; ...                                                                  % Pilot spacing in the frequency domain
    NumberOfSymbolsInTime,...                                                   % Number of OFDM Symbols
    pilot_sep_time ...                                                                 % Pilot spacing in the time domain
    ],...                                   
    'MovingBlockAverage' ,...                                           % Interpolation method: 'MovingBlockAverage' (takes the average of a few close pilots to estimate the channel at the data position), 'FullAverage','linear','nearest','natural'
    [pilot_sep_freq NumberOfSymbolsInTime] ...                                           % For 'MovingBlockAverage' defines the average region in frequency and time    
    );

% Number of samples
N_FBMC = FBMC.Nr.SamplesTotal;
N = N_FBMC;

% PAM and QAM Object
QAM = Modulation.SignalConstellation(QAM_ModulationOrder,'QAM');
if strcmp(FBMC.Method(end-3),'O')
    % FBMC-OQAM transmission, only real valued data symbols
    PAMorQAM = Modulation.SignalConstellation(sqrt(QAM_ModulationOrder),'PAM');
else
    % FBMC-QAM transmission,  complex valued data symbols
    PAMorQAM = Modulation.SignalConstellation(QAM_ModulationOrder,'QAM');
end

% Pre-allocate Transmit Power
Ps_FBMC   = zeros(N_FBMC, 1);

% Pre-allocate Power Spectral Density
PSD_FBMC  = zeros(N_FBMC, 1);


%% Creating cell array of equalizers for each subcarrier
plot_sign = ["LE_RLS"; "DFE_RLS"; "LE_LMS"; "DFE_LMS"; "APF"];% "LE_CMA"; "DFE_CMA"; "MLSE"; "MMSE"; "ZF"];
% plot_sign = ["MLSE"];
num_eq = length(plot_sign);
eq_LE_RLS = comm.LinearEqualizer('Algorithm', 'RLS', 'NumTaps', 1, 'ForgettingFactor', 0.25, 'ReferenceTap', 1);
eq_DFE_RLS = comm.DecisionFeedbackEqualizer('Algorithm', 'RLS', 'NumForwardTaps', 1, 'NumFeedbackTaps', 1, 'ForgettingFactor', 0.25, 'ReferenceTap', 1);
eq_LE_LMS = comm.LinearEqualizer('Algorithm', 'LMS', 'NumTaps', 1, 'StepSize', 0.03, 'ReferenceTap', 1);
eq_DFE_LMS = comm.DecisionFeedbackEqualizer('Algorithm', 'LMS', 'NumForwardTaps', 1, 'NumFeedbackTaps', 1, 'StepSize', 0.03, 'ReferenceTap', 1);
eq_APF = dsp.AffineProjectionFilter('Length', 1, 'ProjectionOrder', 2);
% eq_LE_CMA = comm.LinearEqualizer('Algorithm', 'CMA', 'NumTaps', 5, 'StepSize', 0.01, 'ReferenceTap', 1, 'InitialWeightsSource', 'Property');
% eq_DFE_CMA = comm.DecisionFeedbackEqualizer('Algorithm', 'CMA', 'NumForwardTaps', 1, 'NumFeedbackTaps', 1, 'StepSize', 0.01, 'ReferenceTap', 1);
% const = [-1+1j; -1-1j; 1+1j; 1-1j]./sqrt(2);
% eq_MLSE = comm.MLSEEqualizer('TracebackDepth', 10, 'Constellation', const, 'ChannelSource', 'Property');
eq_array = {eq_LE_RLS; eq_DFE_RLS; eq_LE_LMS; eq_DFE_LMS; eq_APF};% eq_LE_CMA; eq_DFE_CMA; eq_MLSE};
% eq_array = {eq_MLSE};
BER_FBMC_Equalized = zeros(num_eq, length(Simulation_SNR_dB), Simulation_MonteCarloRepetitions);
for j=2:Number_of_carriers
    for k=1:num_eq
        eq_array(k, j) = {eval("eq_"+plot_sign(k))};
    end
end

%% Start Simulation
tic
for i_rep = 1:Simulation_MonteCarloRepetitions

    % Binary data
    BinaryDataStream_FBMC  = randi([0 1], FBMC.Nr.Subcarriers  * FBMC.Nr.MCSymbols  * log2(PAMorQAM.ModulationOrder),1);

    % Map bits to symbols
    x_FBMC  = reshape(PAMorQAM.Bit2Symbol(BinaryDataStream_FBMC), FBMC.Nr.Subcarriers, FBMC.Nr.MCSymbols);
    memory_X{i_rep} = x_FBMC;

    % Transmitted signal in the time domain
    s_FBMC  =  FBMC.Modulation( x_FBMC );

    % ������� ������� � �������������� ������� � �������� ������ 
    % ������������ ���������������� ��������� �� ��������� replayfilter_bb
    r_FBMC_noNoise  = replayfilter_bb(s_FBMC, SamplingRate, h, fs_tau);
    r_FBMC_noNoise = r_FBMC_noNoise(1:length(s_FBMC));

    % Calculate the transmitted power over time
    Ps_FBMC  = Ps_FBMC  + abs(s_FBMC).^2;

    % Calculat the power spectral density
    PSD_FBMC  = PSD_FBMC  + abs(fft(s_FBMC)/sqrt(N_FBMC)).^2;

    for i_SNR = 1:length(Simulation_SNR_dB)
        % Add noise
%         r_FBMC = awgn(r_FBMC_noNoise, Simulation_SNR_dB(i_SNR), 'measured');
        % Add noise
        SNR_dB = Simulation_SNR_dB(i_SNR);
        Pn_time = 1/FBMC.GetSymbolNoisePower(1)*10^(-SNR_dB/10);
        noise = sqrt(Pn_time/2)*(randn(N,1)+1j*randn(N,1));
            
        r_FBMC  = r_FBMC_noNoise  + noise(1:N_FBMC);
        % ����������� ��������
        y_FBMC  =  FBMC.Demodulation(r_FBMC);
        memory_Y{i_rep, i_SNR} = y_FBMC;
    
        param = 0;
        for k=1:num_eq
            % �����������
%         myEqualizers;
        if k <6
            y_Equalized_FBMC = test_Simple_Equalazer(x_FBMC, y_FBMC, eq_array(k,:), true, i_SNR);
        elseif k <9
            y_Equalized_FBMC = test_Simple_Equalazer(x_FBMC, y_FBMC, eq_array(k,:), false, i_SNR);
        else
            CEPM = ChannelEstimation.PilotMatrix;
            y_Equalized_FBMC = myEqualizers_func(y_FBMC, x_FBMC, i_SNR, Number_of_carriers, NumberOfSymbolsInTime, CEPM, pilot_sep_time, param);
            param =+ 1;
        end
        
        memory_Y_eq{i_rep, i_SNR} = y_Equalized_FBMC;

%          y_Equalized_FBMC = y_FBMC;
        % Detect symbols (quantization and demapping to bits)
        DetectedBitStream_Equalized_FBMC  = PAMorQAM.Symbol2Bit(y_Equalized_FBMC(:));

        % Calculate the BER
        % with pilots
%         BER_FBMC_Equalized(k, i_SNR, i_rep)   = mean( BinaryDataStream_FBMC(ChannelEstimation.PilotMatrix==0)...
%             ~=DetectedBitStream_Equalized_FBMC(ChannelEstimation.PilotMatrix==0));
        % without pilots
        BER_FBMC_Equalized(k, i_SNR, i_rep)   = mean( BinaryDataStream_FBMC~=DetectedBitStream_Equalized_FBMC);
        
        end
        
        %BER_eq{k} = BER_FBMC_Equalized;
        
    end
        TimeNeededSoFar = toc;
        if mod(i_rep, 5)==0
            disp([int2str(i_rep/Simulation_MonteCarloRepetitions*100) '% Completed. Time Left, approx. ' int2str(TimeNeededSoFar/i_rep*(Simulation_MonteCarloRepetitions-i_rep)/60) 'min, corresponding to approx. '  int2str(TimeNeededSoFar/i_rep*(Simulation_MonteCarloRepetitions-i_rep)/3600) 'hour'])
        end
end

% constell = comm.ConstellationDiagram('NumInputPorts', 2);
% constell(x_OFDM((ChannelEstimation.PilotMatrix==0)), y_Equalized_OFDM((ChannelEstimation.PilotMatrix==0)))

% Take "average"
Ps_FBMC  = Ps_FBMC/Simulation_MonteCarloRepetitions;
PSD_FBMC = PSD_FBMC/Simulation_MonteCarloRepetitions;
   
%% Plot Stuff
% Plot BER
f = figure;
hold on;
semilogy(Simulation_SNR_dB, mean(BER_FBMC_Equalized, 3)'); 
% for k=1:num_eq
    % semilogy(Simulation_SNR_dB, mean(BER_eq{k},2)); 
% end
%set(f,{'DisplayName'}, plot_sign)
%legend show
legend(plot_sign, 'Interpreter', 'none');