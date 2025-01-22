clear all
clc

%%
% 工程编号ISN-10000
% 这个程序用来把全天时大气产生的数据，进行解析
% 原本有c#程序了，但是这个matlab解析的更加全面
% 功能1. 对原有数据，通过找头，解析出头，并且判断移位的位数
% 功能1. 按照协议解析各个字段
% 功能2. 相同帧号只显示一次
% 功能3. 每一行代表一帧，最后有[移位后的16进制]
% 输入：
% c#保存的dat文件
% 输出：
% 解析后的csv文件

%
% 用来表示移位的案例，这是一个需要左移2位的案例
% 原始16:	FD   CA    86  86  6E
% 原始10: 253  202   134  134  110
% 原始2:  1111 1101 | 1100 1010  | 1000 0110 | 1000 0110 | 0110 1110
% 移后2:  0111 0010 | 1010 0001 | 1010 0001 | 1001 1011 | 10
% 移后16:  72 |  A1 | A1 | 9B
% 移后10:  114  | 161 | 161 | 155

% 打开文件并初始化一些参数
fid = fopen('D:\workdir\data_0-主份-转动.dat', 'rb');
outputFile = 'corrected_data.csv';
headerPattern = repmat(0xFF, 1, 10); % 假设帧头最少10个0xFF
% frameSize = 46; % 仪器数据的字节数
frameSize = 50; % 仪器数据的字节数,原本46，因为防止移位，所以多弄几个

% 打开CSV文件准备写入
csvFID = fopen(outputFile, 'w');


% 写入Header
strHeader = {
'第1路',
'第2路',
'第3路',
'第4路',
'第5路',
'第6路',
'第7路',
'第8路',
'第9路',
'第10路',
'第11路',
'第12路',
'校正仪工作状态字',
'偏振状态字',
'工作周期计数',
'校正仪主体电流',
'时间码',
'指令计数',
'指令校验判断',
'帧计数',
'电机电流',
'电机转动步数',
'电磁阀工作状态',
'备用',
'校验字',
'16进制码'};
strHeaderLine = strjoin(strHeader, ',');
fprintf(csvFID, '%s\n', strHeaderLine); % 写入标题行

% 定义帧头结尾与偏移量的对应关系
headerEndings =  [0xFE, 0xFD, 0xFB, 0xF7, 0xEE, 0xDC, 0xB9, 0x72];
bitShifts = [7, 6, 5, 4, 3, 2, 1, 0];   
tempBuffer = 1:length(headerPattern);   %用于存储帧头的buffer
last_framenum = -1;   %上一帧帧号
while ~feof(fid)
    % 逐字节读取，找帧头
    buffer = fread(fid, 1, 'uint8');
    if(isempty(buffer))
        break;
    end
    
    tempBuffer(1:end-1) = tempBuffer(2:end);
    tempBuffer(end) = buffer;
    
    % 判断是否匹配帧头模式
%     if buffer == 0xFF
        % 读取接下来的若干字节，判断是否符合帧头
%         tempBuffer = fread(fid, length(headerPattern) + 1, 'uint8');
        
        % 比对帧头结尾，确定偏移量
        for i = 1:length(headerEndings)
            if tempBuffer(end) == headerEndings(i)
                bitShift = bitShifts(i);
                break;
            end
        end

        % 如果找到有效帧头，开始读取并矫正46字节的仪器数据
        if exist('bitShift', 'var')
            instrumentData = fread(fid, frameSize, 'uint8');
            if(length(instrumentData)<frameSize)
                break;
            end
           correctedData = zeros(1, frameSize, 'uint8');
            % 矫正数据，跨字节补位
            for j = 1:frameSize
                % 当前字节左移指定位数
                currentByte = bitand(bitshift(instrumentData(j), bitShift), 255);
                
                % 如果不是最后一个字节，则用下一字节的高位补齐
                if j < frameSize
                    nextByte = bitshift(instrumentData(j+1), bitShift - 8); 
                    currentByte = bitor(currentByte, nextByte);
                end
                correctedData(j) = currentByte;
            end
        
            %---- 如果帧号相同，那么就不输出了
            frmnum = correctedData(37);
            if frmnum == last_framenum
                % 清除bitShift以防止误用
                clear bitShift;
                continue;
            end
            
            % 更新帧号
            last_framenum = frmnum;  
            
            %---- 计算部分
            A = correctedData;   % 没有任何意义的屎山代码，就为了后面打字简单
            % 一定要清理resString
            resString = {};
            %计算电压
            for kk=1:12
                tmp_B = [A((kk-1)*2+1),A((kk-1)*2+2)];
                resList(kk) =  calc_BuMa(tmp_B);
            end
            resString{1} =  strjoin(arrayfun(@num2str, resList, 'UniformOutput', false), ',');
            % 工作状态字
            resString{end+1} = num2str(A(25));
            % 偏振状态字
            resString{end+1} = num2str(A(26));
            % 工作周期计数
            resString{end+1} = num2str(A(27));
            % 校正仪主体电流
            resString{end+1} = num2str(A(28));
            % 时间码
            resString{end+1} = strjoin(arrayfun(@num2str, A(29:34), 'UniformOutput', false), '-');
            % 指令计数
            resString{end+1} = num2str(A(35));
            % 指令校验判断
            resString{end+1} = num2str(A(36));
            % 帧计数
            resString{end+1} = num2str(A(37));
            % 电机电流
            tmp_AmpMotor = calc_BuMa(A(38:39));
            resString{end+1} = num2str(tmp_AmpMotor);
            % 电机转动步数
%             tmp_MotorStep = calc_BuMa(A(40:41));   % 这是低字节在前的，施亮改成高字节在前，因此注释掉
            tmp_MotorStep = double(A(40))*256+double(A(41));
            
            resString{end+1} = num2str(tmp_MotorStep);
            % 电磁阀工作状态
            resString{end+1} = num2str(A(42));
            % 备用
            resString{end+1} = strjoin(arrayfun(@num2str, A(43:45), 'UniformOutput', false), '-');
            % 校验字
            resString{end+1} = num2str(A(46));
            % 保存字符串
            resString{end+1} = sprintf('%02X', correctedData);
            
            % 把resString组合成一个大字符串
            csvLine = strjoin(resString, ',');
            % 将矫正的数据写入CSV文件
            fprintf(csvFID, '%s\n', csvLine);
            
            
            % 清除bitShift以防止误用
            clear bitShift;

        end
%     end
end

% 关闭文件
fclose(fid);
fclose(csvFID);


%[低8位 高8位]组成补码，换算原来的值
function B = calc_BuMa(A)

A = double(A);
B = bitshift(A(2), 8) + A(1);       % 将高8位和低8位组合成16位整数

% 检查是否为负数（16位补码的最高位为1表示负数）
if B >= 32768
    B = B - 65536; % 如果B为负数，将其转换为补码的十进制表示
end

end
