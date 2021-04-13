%
% Trace compression by selecting cycle maxima
%
% Ilya Kizhvatov, University of Luxembourg, 2008

%% set up parameters

TraceLength = 100001;%47501;
SamplesPerSecond = 100000000;
ClockFrequency = 3686400;
SamplesPerCycle = SamplesPerSecond / ClockFrequency;
CycleOffset = 0; % determined by eye
TotalCycles = floor(TraceLength / SamplesPerCycle);
disp(sprintf('Samples per cycle: %f', SamplesPerCycle));
disp(sprintf('Total number of full cycles: %d', TotalCycles));

NumTraces = 5120;


%% read out the traces and the corresponding inputs (only for short amount of traces!)

f = fopen('C:/rddata/segments.dat','rb');
Traces = fread(f, [TraceLength NumTraces], 'uint8');
fclose(f);

plot(Traces(1:27, [1 10 100 400]));


%% go ahead with compression

StartCycle = 1;
EndCycle = 1544;
NumCycles = EndCycle - StartCycle + 1;

CompressedTraces = zeros(NumCycles, NumTraces);

for i = 2:NumCycles
    CurrentCycle = Traces((round((i-1) * SamplesPerCycle - CycleOffset) + 1):round(i * SamplesPerCycle - CycleOffset), :);
    CompressedTraces(i,:) = max(CurrentCycle);
end

%% compress a large amount of traces chunk-wise

NumAcquisitions = 10;
TracesPerAcquisition = 200;
NumTraces = TracesPerAcquisition * NumAcquisitions;
TraceLength = 100001;
SamplesPerSecond = 100000000;
ClockFrequency = 3686400;
SamplesPerCycle = SamplesPerSecond / ClockFrequency;
% CycleOffset = 0; % determined by eye
TotalCycles = floor(TraceLength / SamplesPerCycle);
disp(sprintf('Samples per cycle: %f', SamplesPerCycle));
disp(sprintf('Total number of full cycles: %d', TotalCycles));

%
StartCycle = 1;
EndCycle = 3680; %2800;
NumCycles = EndCycle - StartCycle + 1;

Traces = zeros(TraceLength, TracesPerAcquisition, 'uint8');
CompressedTraces = zeros(NumCycles, NumTraces, 'uint8');

f = fopen('C:/rddata/segments.dat','rb');

tic
for i = 1:NumAcquisitions
    Traces = fread(f, [TraceLength TracesPerAcquisition], 'uint8');
    for j = 1:NumCycles
        CompressedTraces(j, ((i - 1) * TracesPerAcquisition + 1):(i * TracesPerAcquisition)) = ...
            max(Traces((round((j-2+StartCycle)*SamplesPerCycle)+1):round((j-1+StartCycle)*SamplesPerCycle),:));
    end
end
toc

fclose(f);
