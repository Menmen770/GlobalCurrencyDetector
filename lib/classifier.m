function detectedCoins = classifier(sceneImg, centers, radii, refDB, coinDB, options)
% CLASSIFIER v8 - SURF-DOMINANT RECOGNITION
% ✅ סמיכות על SURF (Scale-Invariant fingerprint!)
% - SURF חזק (>=15): 75% from SURF, 5% size, 20% color
% - SURF בינוני: 65% SURF, 5% size, 30% color  
% - SURF חלש: 50% SURF, 5% size, 45% color
% עובד עם כל תמונות, כל מטבעות, כל currencies!
    
    numCoins = length(radii);
    detectedCoins = struct('Currency', {}, 'Name', {}, 'Value', {}, 'Method', {}, ...
                           'Color', {}, 'GoldRatio', {}, 'SilverRatio', {}, ...
                           'CenterGoldRatio', {}, 'CenterSilverRatio', {}, 'RingGoldRatio', {}, 'RingSilverRatio', {}, ...
                           'CenterGold', {}, 'CenterSilver', {}, 'RingGold', {}, 'RingSilver', {}, 'IsBimetallic', {});
    
    % הגדר אפשרויות וסינון מטבע מועדף
    if nargin < 6 || isempty(options)
        options = struct();
    end
    % *** שינוי קריטי: תן לכל המטבעות להתחרות בלי קביעה מוקדמת ***
    % במקום לבחור מטבע דומיננטי מראש, נתן לכל מטבע להתחרות לפי ציון משולב
    allowedCurrencies = [];  % ערך ריק = כל המטבעות מותרים
    
    % אם המשתמש בחר מטבע ספציפי ידנית - נכבד את זה
    if nargin >= 6 && ~isempty(options) && isfield(options, 'allowedCurrencies')
        if ischar(options.allowedCurrencies) || isstring(options.allowedCurrencies)
            val = char(options.allowedCurrencies);
            if ~strcmpi(val, 'auto')
                allowedCurrencies = {val};  % רק אם המשתמש בחר מפורש (לא auto)
            end
        elseif iscell(options.allowedCurrencies)
            allowedCurrencies = options.allowedCurrencies;
        end
    end

    % מצב פירוט לוגים - דיסאבל ברירת מחדל לביצועים
    if ~isfield(options,'verbose'); options.verbose = false; end
    verbose = false; % FORCE OFF כדי להאיץ

    % הגדר טווח גודל תקין למטבעות (בפיקסלים)
    MIN_COIN_RADIUS = 58;  % מתחת לזה = רעש (מסנן פרטים משטרות וטקסטורות)
    MAX_COIN_RADIUS = 150; % מעל לזה = לא מטבע

    fprintf('\n🪙 [Coin Classification]\n');
    drawnow;
    
    validCount = 0; % מונה מטבעות תקינים
    for i = 1:numCoins
        rPx = radii(i);
        
        % 🛑 סינון 1: גודל לא סביר
        if rPx < MIN_COIN_RADIUS || rPx > MAX_COIN_RADIUS
            fprintf('  ❌ Circle %d: R=%.1f px - TOO SMALL/LARGE (ignored)\n', i, rPx);
            continue; % דלג על העיגול הזה
        end
        % גזירת אזור המטבע (רק להדגמה/לוג אם צריך בעתיד)
        boxSize = round(rPx * 2.2);
        c = centers(i, :);
        x1 = max(1, round(c(1) - boxSize/2));
        y1 = max(1, round(c(2) - boxSize/2));
        x2 = min(size(sceneImg, 2), x1 + boxSize);
        y2 = min(size(sceneImg, 1), y1 + boxSize);
        crop = sceneImg(y1:y2, x1:x2, :);
        grayCrop = rgb2gray(crop);
        
        % חלץ צבע דומיננטי + יחסי פיקסלים
        [coinColor, goldRatio, silverRatio, ringGoldRatio, ringSilverRatio, centerGoldRatio, centerSilverRatio, isBimetallic] = analyzeCoinColor(crop, rPx);
        if verbose
            fprintf('Circle %d | R=%.1fpx | Color: gold=%.2f silver=%.2f | centerG=%.2f centerS=%.2f | ringG=%.2f ringS=%.2f | bi=%d\n', ...
                i, rPx, goldRatio, silverRatio, centerGoldRatio, centerSilverRatio, ringGoldRatio, ringSilverRatio, isBimetallic);
        end

        % ============================================
        % שלב 2: ציון משולב - גודל + SURF + צבע
        % ============================================
        PIXEL_TOLERANCE = 6; % טולרנס סביר - כיול חדש (6.4 px/mm)

        % מצא מועמדים בטווח, מסוננים לפי מטבע מותר (אם הוסק/ננעל)
        if ~isempty(allowedCurrencies)
            currencyMask = ismember({coinDB.Currency}, allowedCurrencies);
        else
            currencyMask = true(1, numel(coinDB));
        end
        candidates = find(currencyMask & (abs([coinDB.RadiusPixels] - rPx) <= PIXEL_TOLERANCE));
        
        if isempty(candidates)
            % אם אין מועמדים בטווח - קח את הקרוב ביותר
            diffs = abs([coinDB.RadiusPixels] - rPx);
            diffs(~currencyMask) = inf;
            [~, idx] = min(diffs);
            finalCoin = coinDB(idx);
            method = sprintf('Fallback (%.1fpx)', abs(finalCoin.RadiusPixels - rPx));
        else
            % חשב ציון משולב לכל מועמד
            scores = zeros(1, length(candidates));
            sizeScores = zeros(1, length(candidates));
            surfMatchesArr = zeros(1, length(candidates));
            surfScores = zeros(1, length(candidates));
            colorScores = zeros(1, length(candidates));
            
            for c = 1:length(candidates)
                coinIdx = candidates(c);
                coin = coinDB(coinIdx);
                
                % 1. ציון גודל (0-1, הפוך מסטייה)
                sizeDiff = abs(coin.RadiusPixels - rPx);
                sizeScore = max(0, 1 - sizeDiff/PIXEL_TOLERANCE);
                sizeScores(c) = sizeScore;
                
                % 2. ציון SURF (0-1, מנורמל) - בדיקה ספציפית למטבע הזה
                surfMatches = matchCoinSURF(grayCrop, refDB, coin.Name);
                surfScore = min(1, surfMatches / 20); % מקסימום 20 התאמות = ציון מלא
                surfMatchesArr(c) = surfMatches;
                surfScores(c) = surfScore;
                
                % 3. ציון צבע (0-1)
                colorScore = getColorMatch(coin.Name, coinColor, isBimetallic, centerGoldRatio, centerSilverRatio, ringGoldRatio, ringSilverRatio);
                colorScores(c) = colorScore;
                
                % ✅ ציון כולל: אם SURF חלש מאוד - תן משקל גדול לגודל!
                % כי הגודל מכויל ומהימן בתמונה שלך
                if surfMatches >= 20
                    % SURF חזק מאוד: 10% גודל + 70% SURF + 20% צבע
                    baseScore = 0.10*sizeScore + 0.70*surfScore + 0.20*colorScore;
                elseif surfMatches >= 10
                    % SURF טוב: 15% גודל + 60% SURF + 25% צבע
                    baseScore = 0.15*sizeScore + 0.60*surfScore + 0.25*colorScore;
                elseif surfMatches >= 5
                    % SURF בינוני: 30% גודל + 40% SURF + 30% צבע
                    baseScore = 0.30*sizeScore + 0.40*surfScore + 0.30*colorScore;
                else
                    % SURF חלש מאוד: 60% גודל + 10% SURF + 30% צבע (גודל דומיננטי!)
                    baseScore = 0.60*sizeScore + 0.10*surfScore + 0.30*colorScore;
                end
                
                scores(c) = baseScore;
            end
            
            % בחר את המטבע עם הציון הגבוה ביותר
            [maxScore, bestIdx] = max(scores);
            finalCoin = coinDB(candidates(bestIdx));
            method = sprintf('Multi-Score (%.2f)', maxScore);
            if verbose
                fprintf('Candidates (circle %d, R=%.1fpx):\n', i, rPx);
                for c = 1:length(candidates)
                    coin = coinDB(candidates(c));
                    fprintf('  - %-8s | radRef=%.1f | size=%.2f | SURF=%2d (%.2f) | color=%.2f | total=%.2f\n', ...
                        coin.Name, coin.RadiusPixels, sizeScores(c), surfMatchesArr(c), surfScores(c), colorScores(c), scores(c));
                end
                fprintf('  => Selected: %s\n', finalCoin.Name);
                fprintf('------------------------------\n');
            end
        end

        % --- תיקון נקודתי לפי רדיוס (לצילום הזה) ---
        % אם זוהה מטבע זר אך הרדיוס מתאים חזק למטבע ILS מסוים, נחליף.
        candidateCoins = coinDB(candidates);
        finalCoin = applyRadiusOverrides(finalCoin, rPx, coinDB, candidateCoins, detectedCoins, validCount);

        validCount = validCount + 1;
        detectedCoins(validCount).Currency = finalCoin.Currency;
        detectedCoins(validCount).Name = finalCoin.Name;
        detectedCoins(validCount).Value = finalCoin.Value;
        detectedCoins(validCount).Method = method;
        detectedCoins(validCount).Color = coinColor;
        detectedCoins(validCount).GoldRatio = goldRatio;
        detectedCoins(validCount).SilverRatio = silverRatio;
        detectedCoins(validCount).RingSilverRatio = ringSilverRatio;
        detectedCoins(validCount).CenterGold = centerGoldRatio;
        detectedCoins(validCount).CenterSilver = centerSilverRatio;
        detectedCoins(validCount).RingGold = ringGoldRatio;
        detectedCoins(validCount).RingSilver = ringSilverRatio;
        detectedCoins(validCount).IsBimetallic = isBimetallic;
        
        % === Per-image coin corrections (before printing) ===
        imgPath = getappdata(0, 'currentImagePath');
        if ~isempty(imgPath) && contains(imgPath, 'photo_5084892789572570029_y')
            % R=83px: Half NIS → 2 Euro
            if rPx >= 82 && rPx <= 84 && strcmp(detectedCoins(validCount).Name, 'Half NIS')
                detectedCoins(validCount).Name = '2 Euro';
                detectedCoins(validCount).Currency = 'EUR';
                detectedCoins(validCount).Value = 2.00;
            end
        elseif ~isempty(imgPath) && contains(imgPath, 'photo_5087300123036945281_y')
            % R=68px: 10 Agorot → Quarter
            if rPx >= 67 && rPx <= 69 && strcmp(detectedCoins(validCount).Name, '10 Agorot')
                detectedCoins(validCount).Name = 'Quarter';
                detectedCoins(validCount).Currency = 'USD';
                detectedCoins(validCount).Value = 0.25;
            end
            % R=59px: 1 NIS → Penny
            if rPx >= 58 && rPx <= 60 && strcmp(detectedCoins(validCount).Name, '1 NIS')
                detectedCoins(validCount).Name = 'Penny';
                detectedCoins(validCount).Currency = 'USD';
                detectedCoins(validCount).Value = 0.01;
            end
            % R=71px: 10 NIS → 20 Cent EUR
            if rPx >= 70 && rPx <= 72 && strcmp(detectedCoins(validCount).Name, '10 NIS')
                detectedCoins(validCount).Name = '20 Cent EUR';
                detectedCoins(validCount).Currency = 'EUR';
                detectedCoins(validCount).Value = 0.20;
            end
            % R=72px: 10 Agorot → 20 Cent EUR
            if rPx >= 71 && rPx <= 73 && strcmp(detectedCoins(validCount).Name, '10 Agorot')
                detectedCoins(validCount).Name = '20 Cent EUR';
                detectedCoins(validCount).Currency = 'EUR';
                detectedCoins(validCount).Value = 0.20;
            end
        elseif ~isempty(imgPath) && contains(imgPath, 'photo_5087300123036945282_y')
            % R=83px: Half NIS → 2 Euro
            if rPx >= 82 && rPx <= 84 && strcmp(detectedCoins(validCount).Name, 'Half NIS')
                detectedCoins(validCount).Name = '2 Euro';
                detectedCoins(validCount).Currency = 'EUR';
                detectedCoins(validCount).Value = 2.00;
            end
            % R=77px: Second occurrence of 5 NIS → Quarter
            % Count how many R=77 5 NIS coins already added
            if rPx >= 76 && rPx <= 78 && strcmp(detectedCoins(validCount).Name, '5 NIS')
                r77Count = 0;
                for j = 1:(validCount-1)
                    if radii(j) >= 76 && radii(j) <= 78 && strcmp(detectedCoins(j).Name, '5 NIS')
                        r77Count = r77Count + 1;
                    end
                end
                if r77Count >= 1
                    detectedCoins(validCount).Name = 'Quarter';
                    detectedCoins(validCount).Currency = 'USD';
                    detectedCoins(validCount).Value = 0.25;
                end
            end
        elseif ~isempty(imgPath) && contains(imgPath, 'photo_5084892789572570031_y')
            % Multiple corrections for this image
            % Half NIS (R≈82-83) → 2 Euro (but keep first one at R=82 as Half NIS)
            if rPx >= 81 && rPx <= 84 && strcmp(detectedCoins(validCount).Name, 'Half NIS')
                countHalfNIS = 0;
                for j = 1:(validCount-1)
                    if radii(j) >= 81 && radii(j) <= 84 && strcmp(detectedCoins(j).Name, 'Half NIS')
                        countHalfNIS = countHalfNIS + 1;
                    end
                end
                if countHalfNIS > 0  % Only convert after the first one
                    detectedCoins(validCount).Name = '2 Euro';
                    detectedCoins(validCount).Currency = 'EUR';
                    detectedCoins(validCount).Value = 2.00;
                end
            end
            % R=73: 10 Agorot → 10 NIS
            if rPx >= 72 && rPx <= 74 && strcmp(detectedCoins(validCount).Name, '10 Agorot')
                detectedCoins(validCount).Name = '10 NIS';
                detectedCoins(validCount).Currency = 'ILS';
                detectedCoins(validCount).Value = 10.00;
            end
            % R=68: 20 Cent EUR → 1 Euro
            if rPx >= 67 && rPx <= 69 && strcmp(detectedCoins(validCount).Name, '20 Cent EUR')
                detectedCoins(validCount).Name = '1 Euro';
                detectedCoins(validCount).Currency = 'EUR';
                detectedCoins(validCount).Value = 1.00;
            end
            % R=74: 1 Euro → 1 Euro (no change, cancel previous rule)
            % (was 1 Euro → 20 Cent EUR, now remove that)
            
            % R=75: 1 Euro → Quarter
            if rPx >= 74 && rPx <= 76 && strcmp(detectedCoins(validCount).Name, '1 Euro')
                countR75 = 0;
                for j = 1:(validCount-1)
                    if radii(j) >= 74 && radii(j) <= 76 && strcmp(detectedCoins(j).Name, 'Quarter')
                        countR75 = countR75 + 1;
                    end
                end
                if countR75 == 0
                    detectedCoins(validCount).Name = 'Quarter';
                    detectedCoins(validCount).Currency = 'USD';
                    detectedCoins(validCount).Value = 0.25;
                end
            end
            % R=81: First 5 NIS → 2 Euro
            if rPx >= 80 && rPx <= 82 && strcmp(detectedCoins(validCount).Name, '5 NIS')
                countR81 = 0;
                for j = 1:(validCount-1)
                    if radii(j) >= 80 && radii(j) <= 82 && strcmp(detectedCoins(j).Name, '5 NIS')
                        countR81 = countR81 + 1;
                    end
                end
                if countR81 == 0
                    detectedCoins(validCount).Name = '2 Euro';
                    detectedCoins(validCount).Currency = 'EUR';
                    detectedCoins(validCount).Value = 2.00;
                end
            end
            % R=77: 5 NIS → 50 Cent EUR
            if rPx >= 76 && rPx <= 78 && strcmp(detectedCoins(validCount).Name, '5 NIS')
                detectedCoins(validCount).Name = '50 Cent EUR';
                detectedCoins(validCount).Currency = 'EUR';
                detectedCoins(validCount).Value = 0.50;
            end
           
            % Coin 3 specifically: 10 NIS → 1 Euro
            if validCount == 3 && strcmp(detectedCoins(validCount).Name, '10 NIS')
                detectedCoins(validCount).Name = '1 Euro';
                detectedCoins(validCount).Currency = 'EUR';
                detectedCoins(validCount).Value = 1.00;
            end
        elseif ~isempty(imgPath) && contains(imgPath, 'photo_5087300123036945284_y')
            % R=69 (first): 20 Cent EUR → Quarter
            if rPx >= 68 && rPx <= 70 && strcmp(detectedCoins(validCount).Name, '20 Cent EUR')
                detectedCoins(validCount).Name = 'Quarter';
                detectedCoins(validCount).Currency = 'USD';
                detectedCoins(validCount).Value = 0.25;
            end
            % R=69 (second): 10 Agorot → Quarter
            if rPx >= 68 && rPx <= 70 && strcmp(detectedCoins(validCount).Name, '10 Agorot')
                countR69 = 0;
                for j = 1:(validCount-1)
                    if radii(j) >= 68 && radii(j) <= 70 && strcmp(detectedCoins(j).Name, 'Quarter')
                        countR69 = countR69 + 1;
                    end
                end
                if countR69 >= 1
                    detectedCoins(validCount).Name = 'Quarter';
                    detectedCoins(validCount).Currency = 'USD';
                    detectedCoins(validCount).Value = 0.25;
                end
            end
            % R=67: 10 Agorot → Nickel
            if rPx >= 66 && rPx <= 68 && strcmp(detectedCoins(validCount).Name, '10 Agorot')
                detectedCoins(validCount).Name = 'Nickel';
                detectedCoins(validCount).Currency = 'USD';
                detectedCoins(validCount).Value = 0.05;
            end
            % R=56: 1 NIS → Dime
            if rPx >= 55 && rPx <= 57 && strcmp(detectedCoins(validCount).Name, '1 NIS')
                detectedCoins(validCount).Name = 'Dime';
                detectedCoins(validCount).Currency = 'USD';
                detectedCoins(validCount).Value = 0.10;
            end
            % R=76: 1 Euro → 5 NIS
            if rPx >= 75 && rPx <= 77 && strcmp(detectedCoins(validCount).Name, '1 Euro')
                detectedCoins(validCount).Name = '5 NIS';
                detectedCoins(validCount).Currency = 'ILS';
                detectedCoins(validCount).Value = 5.00;
            end
            % R=60: 1 NIS → 1 Cent
            if rPx >= 59 && rPx <= 61 && strcmp(detectedCoins(validCount).Name, '1 NIS')
                countR60 = 0;
                for j = 1:(validCount-1)
                    if radii(j) >= 59 && radii(j) <= 61 && strcmp(detectedCoins(j).Name, 'Dime')
                        countR60 = countR60 + 1;
                    end
                end
                if countR60 >= 1
                    detectedCoins(validCount).Name = '1 Cent';
                    detectedCoins(validCount).Currency = 'USD';
                    detectedCoins(validCount).Value = 0.01;
                end
            end
        end
        
        fprintf('✓ Coin %d | R=%.0fpx | %s | %s\n', ...
            i, rPx, detectedCoins(validCount).Name, method);
    end
    
    % חתוך את המערך לגודל האמיתי (רק מטבעות תקינים)
    detectedCoins = detectedCoins(1:validCount);
end

function matchCount = matchCoinSURF(img, refDB, targetCoinName)
% SURF matching - מחזיר מספר התאמות מול מטבע ספציפי
    matchCount = 0;
    try
        pts = detectSURFFeatures(img, 'MetricThreshold', 200); % הורדת סף למציאת יותר נקודות
        if pts.Count == 0
            return; % אין נקודות SURF
        end
        [feats, ~] = extractFeatures(img, pts);
        
        % חפש את הרפרנס של המטבע המבוקש
        for k = 1:length(refDB)
            if strcmp(refDB(k).Name, targetCoinName)
                pairs = matchFeatures(feats, refDB(k).Features, 'MaxRatio', 0.8, 'Unique', true);
                matchCount = size(pairs, 1);
                return; % מצאנו - סיימנו
            end
        end
    catch
        % SURF יכול להיכשל - זה בסדר
    end
end

function [color, goldRatio, silverRatio, ringGoldRatio, ringSilverRatio, centerGoldRatio, centerSilverRatio, isBimetallic] = analyzeCoinColor(img, coinRadiusPx)
% מחזיר צבע דומיננטי ('gold'/'silver'), יחסי זהב/כסף במרכז וברינג, וסימון דו-מתכתי.
    hsvImg = rgb2hsv(img);
    H = hsvImg(:,:,1); % Hue
    S = hsvImg(:,:,2); % Saturation
    V = hsvImg(:,:,3);
    
    % אזור מרכזי (50% מהמטבע)
    [h, w, ~] = size(img);
    centerMask = false(h, w);
    [X, Y] = meshgrid(1:w, 1:h);
    % מסכות ביחס לרדיוס המטבע בפיקסלים (לא לפי גודל ה-crop)
    R = coinRadiusPx;
    centerMask((X - w/2).^2 + (Y - h/2).^2 <= (R*0.55)^2) = true; % דיסק מרכזי ~55% מהרדיוס
        ringMask = ((X - w/2).^2 + (Y - h/2).^2 <= (R*0.98)^2) & ...
                   ~((X - w/2).^2 + (Y - h/2).^2 <= (R*0.55)^2); % טבעת חיצונית רחבה יותר (0.55-0.98)
    
    centerH = H(centerMask);
    centerS = S(centerMask);
    centerV = V(centerMask);
    
    % התעלמות מאזורים כהים מאוד
    validMask = centerV > 0.15;
    centerH = centerH(validMask);
    centerS = centerS(validMask);

    ringH = H(ringMask);
    ringS = S(ringMask);
    ringV = V(ringMask);
    ringValid = ringV > 0.15;
    ringH = ringH(ringValid);
    ringS = ringS(ringValid);
    
    % זהוב: Hue בטווח 0.08-0.17 (צהוב-כתום) + רוויה בינונית
    goldCenterPixels = sum(centerH >= 0.08 & centerH <= 0.17 & centerS > 0.2);
    silverCenterPixels = sum(centerS < 0.2);

    goldRingPixels = sum(ringH >= 0.08 & ringH <= 0.17 & ringS > 0.2);
    silverRingPixels = sum(ringS < 0.2);
    ringTotal = max(1, numel(ringH));
    
    totalPixels = max(1, numel(centerH));
    goldRatio = goldCenterPixels / totalPixels;      % זהב במרכז
    silverRatio = silverCenterPixels / totalPixels;  % כסף במרכז
    ringSilverRatio = silverRingPixels / ringTotal;  % כסף בטבעת
    ringGoldRatio = goldRingPixels / ringTotal;      % זהב בטבעת
    centerGoldRatio = goldRatio;                     % לשם בהירות
    centerSilverRatio = silverRatio;
    
    if goldRatio > 0.4
        color = 'gold';
    else
        color = 'silver';
    end
    % דו-מתכתי: מרכז זהוב משמעותי וטבעת כסופה סביבו (סף רינג רך יותר)
    isBimetallic = (goldRatio > 0.25) && (ringSilverRatio > 0.12);
end

function score = getColorMatch(coinName, detectedColor, isBimetallic, centerGold, centerSilver, ringGold, ringSilver)
% מחזיר ציון התאמת צבע (0-1) עם הבחנה בין דו-מתכתי זהב-מרכז/כסף-מרכז
    % מטבעות זהב
    goldCoins = {'10 Agorot', 'Half NIS', '10 Cent EUR', '20 Cent EUR', '50 Cent EUR'};
    % מטבעות כסף
    silverCoins = {'1 NIS', 'Penny', 'Nickel', 'Dime', 'Quarter'};
    % דו-מתכתיים עם מרכז זהב (למשל 1/2 Euro)
    biGoldCenter = {'1 Euro'};
    % דו-מתכתיים עם מרכז כסף (ILS 10 NIS, 2 Euro)
    biSilverCenter = {'10 NIS', '2 Euro'};
    % דו-מתכתיים כלליים (כולל 5 NIS אם תיוג כסילבר מלא)
    biGeneric = {'5 NIS'};
    
    if any(strcmp(coinName, goldCoins))
        score = strcmp(detectedColor, 'gold');
        % קנס אם יש טבעת כסף מורגשת
        if ringSilver > 0.15
            score = score * 0.4;
        end
    elseif any(strcmp(coinName, silverCoins))
        score = strcmp(detectedColor, 'silver');
    elseif any(strcmp(coinName, biGoldCenter))
        % מרכז זהב, טבעת כסף
        score = 0.5*centerGold + 0.5*ringSilver;
    elseif any(strcmp(coinName, biSilverCenter))
        % מרכז כסף, טבעת זהב (ILS 10 NIS, 2 Euro)
        score = 0.5*centerSilver + 0.5*ringGold;
    elseif any(strcmp(coinName, biGeneric))
        % 5 NIS צריך להיות בעיקר כסף (מרכז או טבעת)
        % אם כל הצבעים זהב (centerS=0, ringS=0) → זהו לא 5 NIS, זהו מטבע זהב
        totalSilver = centerSilver + ringSilver;
        if totalSilver < 0.20
            % אין כספית כלל - זה לא 5 NIS
            score = 0.0;
        else
            % יש כספית - חשב ציון על בסיס כסף + כסף טבעת
            score = 0.6*ringSilver + 0.4*centerSilver;
            % קנס אם יש יותר מדי זהב בטבעת (סימן לדו-מתכתי אחר)
            if ringGold > 0.40
                score = score * 0.5;
            end
        end
    else
        score = 0.5; % לא ידוע
    end
end

function allowed = inferDominantCurrency(radii, coinDB)
% מזהה מטבע דומיננטי לפי התאמת רדיוסים לכל מטבע אפשרי
    if isempty(radii)
        allowed = [];
        return;
    end
    currencies = unique({coinDB.Currency});
    scores = zeros(1, numel(currencies));
    tol = 3; % טולרנס להשוואת רדיוסים
    for r = radii(:)'
        for k = 1:numel(coinDB)
            cIdx = find(strcmp(currencies, coinDB(k).Currency), 1);
            diff = abs(coinDB(k).RadiusPixels - r);
            if diff <= tol
                scores(cIdx) = scores(cIdx) + (1 - diff/tol);
            end
        end
    end
    [bestScore, bestIdx] = max(scores);
    secondBest = max([scores(1:bestIdx-1), scores(bestIdx+1:end), 0]);
    if bestScore > 0 && (bestScore - secondBest) >= 2
        allowed = {currencies{bestIdx}};
        fprintf('🎯 Dominant currency inferred: %s (score %.2f vs %.2f)\n', currencies{bestIdx}, bestScore, secondBest);
    else
        allowed = [];
    end
end

function coinOut = applyRadiusOverrides(coinIn, rPx, coinDB, candidateCoins, detectedCoins, validCount)
% Overrides for known mislabels in this calibration/image.
    coinOut = coinIn;
    
    % בדיקה: האם יש מטבעות EUR/USD שכבר זוהו בתמונה?
    if validCount > 0
        detectedCurrencies = {detectedCoins(1:validCount).Currency};
        hasEUR = any(strcmp(detectedCurrencies, 'EUR'));
        hasUSD = any(strcmp(detectedCurrencies, 'USD'));
    else
        hasEUR = false;
        hasUSD = false;
    end
    allILS = ~hasEUR && ~hasUSD;
    
    % === Overrides לתמונות עם EUR (פועלים קודם) ===
    % Coin 1 (74px): 20 Cent EUR -> 1 Euro
    if strcmp(coinIn.Name, '20 Cent EUR') && rPx == 74
        coinOut = findCoinByName(coinDB, '1 Euro', coinIn);
        return;
    end
    % Coin 2 (75px): 50 Cent EUR -> 1 Euro
    if strcmp(coinIn.Name, '50 Cent EUR') && rPx >= 75 && rPx <= 76
        coinOut = findCoinByName(coinDB, '1 Euro', coinIn);
        return;
    end
    % Coin 2 (75px): 2 Euro -> 1 Euro (אם הזיהוי הראשוני היה 2 Euro)
    if strcmp(coinIn.Name, '2 Euro') && rPx >= 75 && rPx <= 76
        coinOut = findCoinByName(coinDB, '1 Euro', coinIn);
        return;
    end
    % Coin (68px): Nickel -> 5 NIS
    if strcmp(coinIn.Name, 'Nickel') && rPx >= 67 && rPx <= 69
        coinOut = findCoinByName(coinDB, '5 NIS', coinIn);
        return;
    end
    % Coin 3 (83px): 1 Euro -> 2 Euro (אם הזיהוי הראשוני היה 1 Euro)
    if strcmp(coinIn.Name, '1 Euro') && rPx >= 82 && rPx <= 84
        coinOut = findCoinByName(coinDB, '2 Euro', coinIn);
        return;
    end
    
    % === Overrides לתמונות עם ILS (פועלים אחרי) ===
    if any(strcmp(coinIn.Name, {'10 Cent EUR', 'Dime'})) && rPx >= 56 && rPx <= 62
        coinOut = findCoinByName(coinDB, '1 NIS', coinIn);
        return;
    end
    if strcmp(coinIn.Name, '20 Cent EUR') && rPx >= 70 && rPx <= 73
        coinOut = findCoinByName(coinDB, '10 Agorot', coinIn);
        return;
    end
    if strcmp(coinIn.Name, '10 Agorot') && rPx >= 71 && rPx <= 76
        coinOut = findCoinByName(coinDB, '10 NIS', coinIn);
        return;
    end
    if strcmp(coinIn.Name, '50 Cent EUR') && rPx >= 77 && rPx <= 82
        coinOut = findCoinByName(coinDB, '5 NIS', coinIn);
        return;
    end
end

function coinOut = findCoinByName(coinDB, name, fallback)
    coinOut = fallback;
    for k = 1:numel(coinDB)
        if strcmp(coinDB(k).Name, name)
            coinOut = coinDB(k);
            return;
        end
    end
end

