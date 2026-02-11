function currencyType = detectCurrencyType(img)
% DETECTCURRENCYTYPE - מזהה האם התמונה מכילה מטבעות או שטרות
%   Output: 'coins' או 'banknotes'

    % הנורמליזציה של התמונה
    if size(img, 3) == 3
        gray = rgb2gray(img);
    else
        gray = img;
    end
    
    % ====== בדיקה 1: חפש עיגולים (מטבעות) ======
    [centers, radii] = imfindcircles(gray, [58 150], ...
        'ObjectPolarity', 'bright', ...
        'Sensitivity', 0.85);
    
    numCircles = length(radii);
    
    % ====== בדיקה 2: חפש מלבנים גדולים (שטרות) ======
    % שטר בדרך כלל תופס חלק גדול מהתמונה
    try
        processed = imclearborder(imbinarize(gray, graythresh(gray)));
        stats = regionprops(processed, 'BoundingBox', 'Area');
        
        % חפש אובייקטים גדולים (יותר מ-10% מהתמונה)
        largeObjects = sum([stats.Area] > (size(gray,1)*size(gray,2)*0.1));
    catch
        largeObjects = 0;
    end
    
    % ====== החלטה ======
    % אובייקטים גדולים = כנראה שטרות
    % עיגולים רבים ללא אובייקטים גדולים = מטבעות
    
    if largeObjects >= 1
        % יש אובייקט גדול אחד לפחות → ברירת מחדל היא שטרות
        % רק אם יש הרבה עיגולים (פי 3 ויותר) נחליט שזה מטבעות
        if numCircles >= largeObjects * 3 && numCircles >= 5
            currencyType = 'coins';
            confidence = numCircles;
        else
            currencyType = 'banknotes';
            confidence = largeObjects;
        end
    elseif numCircles >= 2
        % אין אובייקטים גדולים אבל יש 2+ עיגולים → מטבעות
        currencyType = 'coins';
        confidence = numCircles;
    else
        % במקרה ספק (עיגול 1 או 0, ללא אובייקטים גדולים) → נסה מטבעות
        currencyType = 'coins';
        confidence = max(1, numCircles);
    end
    
    % הדפס לוג
    fprintf('💡 Currency Detection:\n');
    fprintf('   - Circles found: %d\n', numCircles);
    fprintf('   - Large objects: %d\n', largeObjects);
    fprintf('   ✅ Decision: %s (confidence: %d)\n\n', currencyType, confidence);
end
