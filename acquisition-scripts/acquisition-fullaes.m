%
% Acquisition for full AES
%
% Ilya Kizhvatov, University of Luxembourg, 2008

%% Create a DSO object and connect to the DSO
 
scope = actxserver('LeCroy.ActiveDSOCtrl.1'); % create a windowless ActiveDSO control
scope.MakeConnection('IP:192.168.0.2');       % connect via TCP/IP (modify the address if needed)
scope.WriteString('BUZZ BEEP', true);         % indicate that we have connectedd
scope.WriteString('*IDN?', true);             % Query the scope name and model number
scopeID = scope.ReadString(1000);             % Read back the scope ID to verify connection
disp(scopeID);

% Set the parameters and preallocate the arrays

% acqusition constants (DSO-dependent)
SegmentsPerTrace = 200;
TraceLength = 20000200;

% experiment parameters
NumTraces = 1000;
NumInputs = NumTraces * SegmentsPerTrace;

% preallocate trace buffer and buffer for ciphertext reception
trace = zeros(1, TraceLength, 'uint8');
ciphertext = zeros(NumInputs, 16, 'uint8');

% generate array of random plaintexts
rand('twister', sum(100*clock));
plaintext = uint8(floor(256.*rand(NumInputs, 16)));
save('C:/rddata/plaintext', 'plaintext');

% generate pool of randm numbers to be sent to the device
RandomPoolSize = 101;
randompool = uint8(floor(256.*rand(NumInputs, RandomPoolSize)));
%randompool = 0 * ones(NumInputs, RandomPoolSize, 'uint8') - 0;


% Acquire the data

% open the file for output
f = fopen('C:/rddata/segments.dat','wb');

% set up and open a serial port...
s = serial('COM1','BaudRate', 115200, 'DataBits', 8, 'StopBits', 1, 'Parity', 'none', 'Terminator', '', 'FlowControl', 'none', 'RequestToSend', 'off', 'DataTerminalReady', 'off');
fopen(s);
% ...and don't forget to close it later on!

% The DSO channels, trigger, resolution, averaging, segments, etc. are
%  supposed to be set up manually, here just calibrate
scope.WriteString('vbs app.Acquisition.Calibrate', true); % clear DSO's channel memories
scope.WaitForOPC();

disp('Starting acquisition in sequence mode...')

tic
for i = 1:NumTraces

    scope.WriteString('vbs app.ClearSweeps', true); % Just for safety
    scope.WaitForOPC();                          % SYNCHRONIZATION!
    scope.WriteString('TRMD SINGLE;ARM', true);  % arm the trigger
    scope.WaitForOPC();                          % SYNCHRONIZATION!
    
    for j = 1:SegmentsPerTrace
        fwrite(s, randompool((i - 1) * SegmentsPerTrace + j, :), 'uint8');
        fwrite(s, plaintext((i - 1) * SegmentsPerTrace + j, :), 'uint8');
        r = fread(s, 1, 'uchar'); % read single response byte for sync
    end
    
    % SYNC! Missed the scope a single trigger, he will get stuck here for a
    % timeout period - but this should not occur as the scope is fast
    % enough to capture all the 500 trigger events in a shot.
    % Make sure that the sequence mode timeout on the scope is larger than
    % the whole segments capture time
    scope.WriteString('WAIT', true);
    scope.WaitForOPC();

    % now get the segmented waveform and write it to the file
    trace = scope.GetByteWaveform('C2', TraceLength, 0); % get wavefrom data
    if (numel(trace) ~= TraceLength)
        disp('DSO missed some traces, breaking the acqusition');
        break;
    end
    fwrite(f, trace, 'uint8');

    % some debug printout
    text = sprintf('trace %d', i);
    disp(text);
end
Duration = toc;

% show timing information
disp(sprintf('Acquisition time: %d s', round(Duration)));
disp(sprintf('Acquisition rate: %d traces/s', round(NumInputs / Duration)));

fclose(f);
fclose(s);
scope.WriteString('BUZZ BEEP', true);

% Close connection to the scope

scope.WriteString('BUZZ BEEP', true); % signal that we are going to disconnect
scope.WaitForOPC();
scope.Disconnect();


%% check single run with min/max delay

s = serial('COM1','BaudRate', 115200, 'DataBits', 8, 'StopBits', 1, 'Parity', 'none', 'Terminator', '', 'FlowControl', 'none', 'RequestToSend', 'off', 'DataTerminalReady', 'off');
fopen(s);
randpool = 255 * ones(101, 1, 'uint8') - 0;
pt = zeros(16, 1, 'uint8') + 255;
for i = 1:1
    fwrite(s, randpool, 'uint8'); % send RNG pool data
    fwrite(s, pt, 'uint8'); % send plaintext
    ct = fread(s, 1, 'uint8'); % 1 sync byte in reply
end
disp(ct);
fclose(s);
