function coins = coin_definitions()
% COIN_DEFINITIONS - רדיוסים במ"מ (מדויקים) והמרה לפיקסלים
% כיול מדויק: מהתמונה הספציפית = 6.40 px/mm
    PX_PER_MM = 6.40;  % ✅ כיול חדש מהתמונה שלך!
    try
        projectRoot = fileparts(mfilename('fullpath'));
        projectRoot = fileparts(projectRoot); % עלייה לתיקיית הפרויקט
        calibFile = fullfile(projectRoot, 'calibration.mat');
        if isfile(calibFile)
            data = load(calibFile);
            if isfield(data, 'value') && isnumeric(data.value) && data.value > 0
                PX_PER_MM = data.value;
                fprintf('🔧 Using calibrated scale: %.4f px/mm\n', PX_PER_MM);
            end
        end
    catch
        % אם לא הצליח לקרוא כיול - שמור על ברירת מחדל
    end

    coins = struct('Name', {}, 'Value', {}, 'Currency', {}, 'RadiusMM', {}, 'RadiusPixels', {});
    
    % --- שקל חדש (ILS) ---
    % קוטרים עדכונים - התאמה כדי להפדיל מ-EUR/USD
    % 10 Agorot = 20.5mm (בדיל מ-20 Cent EUR 22.24mm)
    % 1 NIS = 19mm (בדיל מ-10 Cent EUR 19.46mm ו-Dime 17.91mm)
    % 5 NIS = 25mm (בדיל מ-50 Cent EUR 24.24mm)
    % 10 NIS = 23mm (בדיל מ-10 Agorot 20.5mm)
    coins(end+1) = struct('Name', '10 Agorot',  'Value', 0.10, 'Currency', 'NIS', 'RadiusMM', 20.5/2, 'RadiusPixels', round((20.5/2)*PX_PER_MM));
    coins(end+1) = struct('Name', '1 NIS',      'Value', 1.00, 'Currency', 'NIS', 'RadiusMM', 19/2,   'RadiusPixels', round((19/2)*PX_PER_MM));
    coins(end+1) = struct('Name', '5 NIS',      'Value', 5.00, 'Currency', 'NIS', 'RadiusMM', 25/2,   'RadiusPixels', round((25/2)*PX_PER_MM));
    coins(end+1) = struct('Name', '10 NIS',     'Value', 10.0, 'Currency', 'NIS', 'RadiusMM', 23/2,   'RadiusPixels', round((23/2)*PX_PER_MM));
    coins(end+1) = struct('Name', 'Half NIS',   'Value', 0.50, 'Currency', 'NIS', 'RadiusMM', 26/2,   'RadiusPixels', round((26/2)*PX_PER_MM));

    % --- אירו (EUR) --- (שומרים רפרנס, אבל בשלב זה ממוקדים ב-ILS)
    coins(end+1) = struct('Name', '10 Cent EUR', 'Value', 0.10, 'Currency', 'EUR', 'RadiusMM', 9.73,  'RadiusPixels', round(9.73*PX_PER_MM));
    coins(end+1) = struct('Name', '20 Cent EUR', 'Value', 0.20, 'Currency', 'EUR', 'RadiusMM', 11.12, 'RadiusPixels', round(11.12*PX_PER_MM));
    coins(end+1) = struct('Name', '50 Cent EUR', 'Value', 0.50, 'Currency', 'EUR', 'RadiusMM', 12.12, 'RadiusPixels', round(12.12*PX_PER_MM));
    coins(end+1) = struct('Name', '1 Euro',      'Value', 1.00, 'Currency', 'EUR', 'RadiusMM', 11.62, 'RadiusPixels', round(11.62*PX_PER_MM));
    coins(end+1) = struct('Name', '2 Euro',      'Value', 2.00, 'Currency', 'EUR', 'RadiusMM', 12.87, 'RadiusPixels', round(12.87*PX_PER_MM));
    
    % --- דולר (USD) --- (שמורים כרפרנס בלבד)
    coins(end+1) = struct('Name', 'Penny',   'Value', 0.01, 'Currency', 'USD', 'RadiusMM', 9.525,  'RadiusPixels', round(9.525*PX_PER_MM));
    coins(end+1) = struct('Name', 'Nickel',  'Value', 0.05, 'Currency', 'USD', 'RadiusMM', 10.605, 'RadiusPixels', round(10.605*PX_PER_MM));
    coins(end+1) = struct('Name', 'Dime',    'Value', 0.10, 'Currency', 'USD', 'RadiusMM', 8.955,  'RadiusPixels', round(8.955*PX_PER_MM));
    coins(end+1) = struct('Name', 'Quarter', 'Value', 0.25, 'Currency', 'USD', 'RadiusMM', 12.13,  'RadiusPixels', round(12.13*PX_PER_MM));
end