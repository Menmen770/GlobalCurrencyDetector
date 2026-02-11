function main()
% MAIN_SYSTEM v5 - זיהוי מטבעות ושטרות תמיד יחד
    close all; clc;

    % --- 1. הגדרת נתיבים ---
    projectRoot = fileparts(mfilename('fullpath'));
    addpath(fullfile(projectRoot, 'lib')); 
    imagesDir = fullfile(projectRoot, 'images'); 
    
    % Toggle: auto-load first image on startup (false = always ask)
    autoLoadFirstImage = false;
    % נעילת מטבעות/שטרות לפי מדינה (לדיוק 100% בשלבים)
    coinCurrencyLock = 'auto';  % 'ILS' | 'EUR' | 'USD' | 'auto'
    banknoteCurrencyLock = 'auto';

    % --- 2. טעינת מסד הנתונים ---
    f = waitbar(0, 'Loading Databases... Please Wait');
    try
        coinDB = coin_definitions();
        banknoteDB = banknote_definitions();
        waitbar(0.3, f, 'Loading Coin References...');
        coinRefDB = loadCoinDatabase();
        waitbar(0.6, f, 'Loading Banknote References...');
        banknoteRefDB = loadBanknoteDatabase();
    catch ME
        close(f);
        errordlg(sprintf('Error loading system: %s\nCheck "lib" folder.', ME.message), 'Setup Error');
        return;
    end
    waitbar(1, f, 'Ready!');
    pause(0.5); close(f);

    % --- 3. בחירת קובץ ראשוני ---
    % כדי למנוע תקיעות בחלון הבחירה, ניתן להפעיל/לכבות טעינה אוטומטית של תמונה ראשונה
    initialFilePath = '';
    if autoLoadFirstImage
        try
            imgList = [dir(fullfile(imagesDir, '*.jpg')); dir(fullfile(imagesDir, '*.png')); dir(fullfile(imagesDir, '*.jpeg'))];
            if ~isempty(imgList)
                initialFilePath = fullfile(imgList(1).folder, imgList(1).name);
            end
        catch
            % אם יש בעיה ברשימת קבצים, נמשיך למסך בחירה
        end
    end
    
    if isempty(initialFilePath)
        [file, path] = uigetfile({'*.jpg;*.png;*.jpeg', 'Image Files'}, 'Select Image', imagesDir);
        if isequal(file, 0)
            disp('No file selected. Exiting.');
            return;
        end
        initialFilePath = fullfile(path, file);
    end

    % --- 4. בניית הממשק (GUI) ---
    fig = uifigure('Name', 'Global Currency & Banknote Detector', ...
        'Position', [200 200 950 580], ...
        'Color', [0.93 0.93 0.93]);

    % הגדרת גריד ראשי
    grid = uigridlayout(fig, [1, 2]);
    grid.ColumnWidth = {600, 290};
    grid.Padding = [8 8 8 8];
    grid.RowSpacing = 8;
    grid.ColumnSpacing = 8;

    % --- פאנל שמאל: תמונה ---
    pnlImage = uipanel(grid);
    pnlImage.Layout.Row = 1;
    pnlImage.Layout.Column = 1;
    pnlImage.Title = 'תוצאות הזיהוי';
    pnlImage.BackgroundColor = 'white';
    pnlImage.FontSize = 13;
    pnlImage.FontWeight = 'bold';
    pnlImage.ForegroundColor = [0.1 0.1 0.1];

    ax = uiaxes(pnlImage);
    ax.Position = [8 8 580 520];
    ax.Visible = 'off'; 
    % השאר אינטראקטיביות: zoom, pan, data cursor
    axtoolbar(ax, {'zoomin', 'zoomout', 'pan', 'restoreview'});

    % --- פאנל ימין: שליטה ונתונים ---
    pnlControl = uipanel(grid);
    pnlControl.Layout.Row = 1;
    pnlControl.Layout.Column = 2;
    pnlControl.Title = 'Total';
    pnlControl.FontSize = 13;
    pnlControl.FontWeight = 'bold';
    pnlControl.ForegroundColor = [0.1 0.1 0.1];
    
    % גריד פנימי - 3 שורות: כפתור, טבלה, סיכום
    pnlLayout = uigridlayout(pnlControl, [3, 1]);
    pnlLayout.RowHeight = {45, '1x', 40};
    pnlLayout.Padding = [6 6 6 6];
    pnlLayout.RowSpacing = 6;

    % כפתור טעינת תמונה (למעלה) - נגדיר את הפונקציה מאוחר יותר
    btn = uibutton(pnlLayout);
    btn.Layout.Row = 1;
    btn.Text = '📂 Load Image';
    btn.FontSize = 13;
    btn.FontWeight = 'bold';
    btn.BackgroundColor = [0.15 0.45 0.75];
    btn.FontColor = 'white';

    % טבלה (באמצע)
    tbl = uitable(pnlLayout);
    tbl.Layout.Row = 2;
    tbl.ColumnName = {'Item', 'Count', 'Value'};
    tbl.RowName = {};
    tbl.FontSize = 11;
    
    % תווית סיכום (למטה)
    lblTotal = uilabel(pnlLayout);
    lblTotal.Layout.Row = 3;
    lblTotal.Text = 'Processing...';
    lblTotal.FontSize = 12;
    lblTotal.FontWeight = 'bold';
    lblTotal.HorizontalAlignment = 'center';
    lblTotal.VerticalAlignment = 'center';
    lblTotal.BackgroundColor = [0.87 0.92 0.97];
    lblTotal.FontColor = [0.1 0.1 0.1];

    % --- 5. קישור הכפתור (אחרי שכל המשתנים מוגדרים) ---
    btn.ButtonPushedFcn = @(b,e) onButtonPush(fig, ax, tbl, lblTotal, imagesDir, coinRefDB, coinDB, banknoteRefDB, banknoteDB);

    % --- 6. הרצת התמונה הראשונה (אם קיימת) ---
    if ~isempty(initialFilePath)
        processAndDisplay(initialFilePath, fig, ax, tbl, lblTotal, coinRefDB, coinDB, banknoteRefDB, banknoteDB);
    else
        lblTotal.Text = 'Select an image to start';
    end

    % ---------------------------------------------------------
    % --- פונקציות עזר ---
    % ---------------------------------------------------------

    function onButtonPush(fig, ax, tbl, lblTotal, defaultDir, coinRefDB, coinDB, banknoteRefDB, banknoteDB)
        % תמיד פותח חלון בחירה כדי לאפשר למשתמש לבחור תמונה
        [f, p] = uigetfile({'*.jpg;*.png;*.jpeg', 'Image Files'}, 'Select Image', defaultDir);
        if isequal(f, 0), return; end
        selectedPath = fullfile(p, f);
        processAndDisplay(selectedPath, fig, ax, tbl, lblTotal, coinRefDB, coinDB, banknoteRefDB, banknoteDB);
    end

    function processAndDisplay(currentPath, fig, ax, tbl, lblTotal, coinRefDB, coinDB, banknoteRefDB, banknoteDB)
        clc; % ניקוי המסוף לפני כל הרצה כדי לראות לוגים חדשים
        fprintf('\n=== Processing Image: %s ===\n\n', currentPath);
        drawnow; % כפה עדכון של המסוף
        set(fig, 'Pointer', 'watch'); drawnow;
        try
            % 1. עיבוד תמונה
            [resizeImg, ~, blurredImg, ~] = image_utils(currentPath);
            
            % וודא שהתמונות הן RGB (3 ערוצים)
            if size(resizeImg, 3) == 1
                resizeImg = repmat(resizeImg, [1 1 3]);
            end
            if size(blurredImg, 3) == 1
                blurredImg = repmat(blurredImg, [1 1 3]);
            end

            % 1b. אם יש רקע שמור, הפק מסכת קדמה ויצר תמונה ממוסכת
            bg = [];
            mask = [];
            try
                bg = background_model('load');
            catch
                bg = [];
            end
            if ~isempty(bg)
                % וודא שהרקע הוא RGB
                if size(bg, 3) == 1
                    bg = repmat(bg, [1 1 3]);
                end
                try
                    mask = background_model('mask', resizeImg, bg);
                catch
                    mask = [];
                end
            end

            % לא נשתמש במסכה לזיהוי מטבעות - זה גורם לבעיות!
            % פשוט נעביר את התמונות המקוריות
            maskedColor = resizeImg;
            maskedBlur = blurredImg;
            
            % 2. בדיקה ראשונית: מה יש בתמונה?
            currencyType = detectCurrencyType(resizeImg);
            % תמיד נריץ במצב Auto כדי לזהות גם מטבעות וגם שטרות
            mode = 'Auto';
            
            % 3. ניקוי וציור
            cla(ax);
            imshow(resizeImg, 'Parent', ax);
            hold(ax, 'on');
            
            allDetections = struct('Currency', {}, 'Name', {}, 'Value', {}, 'Method', {});
            banknoteRects = [];
            
            % 4. זיהוי שטרות (רק אם המצב מתאים)
            if strcmp(mode,'Auto') || strcmp(mode,'Banknotes Only')
                [banknoteRects, ~] = detector_banknotes(maskedColor, banknoteRefDB, banknoteDB);
            else
                banknoteRects = [];
            end
            if ~isempty(banknoteRects)
                detectedBanknotes = classifier_banknotes(resizeImg, banknoteRects, banknoteRefDB, banknoteDB);
                
                % ציור שטרות (רק אלה שזוהו בהצלחה)
                for i = 1:length(detectedBanknotes)
                    bbox = detectedBanknotes(i).BBox;  % משתמש ב-BBox מהזיהוי
                    rectangle(ax, 'Position', bbox, 'EdgeColor', 'cyan', 'LineWidth', 2);
                    
                    name = detectedBanknotes(i).Name;
                    text(ax, bbox(1)+10, bbox(2)+25, name, 'Color', 'cyan', 'FontSize', 14, ...
                        'FontWeight', 'bold', 'BackgroundColor', 'black', 'Margin', 2);
                end
                
                % הכן גרסה לחיבור עם מטבעות - רק שדות בסיסיים
                if ~isempty(detectedBanknotes)
                    for k = 1:length(detectedBanknotes)
                        bn = detectedBanknotes(k);
                        allDetections(end+1).Currency = bn.Currency;
                        allDetections(end).Name = bn.Name;
                        allDetections(end).Value = bn.Value;
                        allDetections(end).Method = bn.Method;
                    end
                end
                
                % עדכן את banknoteRects לסינון מטבעות
                banknoteRects = reshape([detectedBanknotes.BBox], 4, [])';
            end
            
            % 5. זיהוי מטבעות (סינון מטבעות בתוך שטרות)
            centers = [];
            radii = [];
            % מריץ תמיד כדי לא להיות תלוי בהחלטת מצב ראשונית
            [centers, radii] = detector(maskedBlur, 0.85); % רגישות יציבה למניעת ריבוי עיגולים דמיוניים
            if ~isempty(centers)
                % וודא שcenters הוא מטריצה nx2 (במקרה של מטבע בודד)
                if size(centers, 1) == 1 && size(centers, 2) ~= 2
                    centers = centers';
                end
                
                % סינון קודם: הסר מטבעות בתוך או חופפים לשטרות לפני הסיווג
                toKeep = true(size(centers, 1), 1);
                for ci = 1:size(centers, 1)
                    c = centers(ci, :);
                    r = radii(ci);
                    
                    for bi = 1:size(banknoteRects, 1)
                        bbox = banknoteRects(bi, :);
                        % גבולות השטר
                        bLeft = bbox(1);
                        bRight = bbox(1) + bbox(3);
                        bTop = bbox(2);
                        bBottom = bbox(2) + bbox(4);
                        
                        % בדוק אם מרכז המטבע בתוך השטר (בלי margin - רק אם ממש בתוך)
                        if c(1) >= bLeft && c(1) <= bRight && c(2) >= bTop && c(2) <= bBottom
                            toKeep(ci) = false;
                            break;
                        end
                    end
                end
                
                % סנן לפני קריאה ל-classifier
                centers = centers(toKeep, :);
                radii = radii(toKeep);
                
                % עכשיו סווג רק מטבעות שנשארו
                if ~isempty(centers)
                    coinOptions = struct();
                    % אם מצב Coins Only ויש נעילה → השתמש בה, אחרת Auto
                    if strcmpi(mode,'Coins Only') && ~strcmpi(coinCurrencyLock,'auto')
                        coinOptions.allowedCurrencies = coinCurrencyLock;
                    else
                        coinOptions.allowedCurrencies = 'auto';
                    end
                    coinOptions.verbose = true; % הדפס לוגים מפורטים לסיוע בכיול
                    detectedCoins = classifier(resizeImg, centers, radii, coinRefDB, coinDB, coinOptions);
                    
                    % ציור מטבעות
                    viscircles(ax, centers, radii, 'Color', 'g', 'LineWidth', 1.5);
                    for i = 1:length(detectedCoins)
                        c = centers(i,:);
                        name = detectedCoins(i).Name;
                        col = 'yellow';
                        if contains(detectedCoins(i).Method, 'Fallback')
                            col = [1 0.5 0];
                        end
                        text(ax, c(1), c(2), name, 'Color', col, 'FontSize', 10, ...
                            'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
                            'BackgroundColor', 'black', 'Margin', 1);
                    end
                    % הוסף לתוצאות - רק שדות בסיסיים
                    for k = 1:length(detectedCoins)
                        coin = detectedCoins(k);
                        allDetections(end+1).Currency = coin.Currency;
                        allDetections(end).Name = coin.Name;
                        allDetections(end).Value = coin.Value;
                        allDetections(end).Method = coin.Method;
                    end
                end
            end

            hold(ax, 'off');
            
            if isempty(allDetections)
                uialert(fig, 'No items detected.', 'Info');
                tbl.Data = {};
                lblTotal.Text = 'No items found';
            else
                updateTable(allDetections, tbl, lblTotal);
            end
            
        catch ME
            uialert(fig, ME.message, 'Error');
        end
        set(fig, 'Pointer', 'arrow');
    end



    function updateTable(items, tbl, lblTotal)
        if isempty(items), tbl.Data = {}; lblTotal.Text = ''; return; end
        
        names = {items.Name};
        uniques = unique(names);
        data = {};
        totalILS = 0; totalEUR = 0; totalUSD = 0;
        
        for i = 1:length(uniques)
            n = uniques{i};
            mask = strcmp(names, n);
            count = sum(mask);
            
            first = items(find(mask,1));
            val = first.Value;
            curr = strtrim(first.Currency); % הסרת רווחים מיותרים
            
            totalVal = count * val;
            data(end+1, :) = {n, count, sprintf('%.2f %s', totalVal, curr)};
            
            % השוואה ללא תלות ברישיות ורווחים
            if strcmpi(curr, 'ILS') || strcmpi(curr, 'NIS'), totalILS = totalILS + totalVal; end
            if strcmpi(curr, 'EUR'), totalEUR = totalEUR + totalVal; end
            if strcmpi(curr, 'USD'), totalUSD = totalUSD + totalVal; end
        end
        tbl.Data = data;
        
        % סיכום
        lblTotal.Text = sprintf('Total: %.2f NIS  |  %.2f EUR  |  %.2f USD', totalILS, totalEUR, totalUSD);
    end
end
