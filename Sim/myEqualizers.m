%% Pilots
h_pilot = zeros(Number_of_carriers, NumberOfSymbolsInTime);
H_pilot = zeros(Number_of_carriers, NumberOfSymbolsInTime);
h_pilot(ChannelEstimation.PilotMatrix==1)=conj(y_FBMC(ChannelEstimation.PilotMatrix==1))...
    ./conj(x_FBMC(ChannelEstimation.PilotMatrix==1));
tmp_index = (ChannelEstimation.PilotMatrix==1);
for i_eql=1:pilot_sep_time:NumberOfSymbolsInTime
    tmp_line_index = tmp_index(:, i_eql);
    tmp_line_index = find(tmp_line_index);
    H_pilot(:, i_eql) = interp1(tmp_line_index, h_pilot(tmp_line_index, i_eql)', 1:1:Number_of_carriers, 'spline');
end
% Условие ниже можно заменить на интерполяцию, а не просто использование
% предыдущих вычислений
if pilot_sep_time > 1
    rem = H_pilot(:, 1);
    for i_eql=2:1:NumberOfSymbolsInTime
        if sum(abs(H_pilot(:, i_eql))) == 0
            H_pilot(:, i_eql) = rem;
        else
            rem = H_pilot(:, i_eql);
        end
    end
end
%% LS equalization
% y_Equalized_FBMC  =  y_FBMC./H_pilot;
%% ZF equalization (по виду тоже самое что и LS)
% [y_Equalized_FBMC, csiZF] = lteEqualizeZF(y_FBMC, H_pilot);
%% MMSE equalization (хм... работает не лучше чем LS)
[y_Equalized_FBMC, csiMMSE] = lteEqualizeMMSE(y_FBMC, H_pilot, Simulation_SNR_dB(i_SNR));
%% Full equalization (all - pilots)
%H_real = y_FBMC./x_FBMC;
%y_Equalized_FBMC  =  y_FBMC./H_real;  