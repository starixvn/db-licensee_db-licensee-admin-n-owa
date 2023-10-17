/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_HighForexExplanation]
	@PartyIds					VARCHAR(MAX)
	,@FromDate					DATE
	,@ToDate					DATE
	,@PlatformId				TINYINT = 0
	,@FilterType_CNY			TINYINT = 0 --(0:None, 1: Is Between, 2: Is Not Between) 
	,@MinValue_CNY				MONEY = -500
	,@MaxValue_CNY				MONEY = 500
	,@FilterType_EUR			TINYINT= 0 --(0:None, 1: Is Between, 2: Is Not Between)
	,@MinValue_EUR				MONEY = -100
	,@MaxValue_EUR				MONEY = 100

AS
/*	Header:
	Created: 20230704@Danny
	Task : Get licensee reconciliation high forex data
	DB: DBLIC.bodb_licensee

	Revisions: 
		- 20230704@Danny: Create Sp [#179232]
*/
BEGIN
	SET NOCOUNT ON

	-- Get Party List
	IF ISNULL(@PlatformId, 0) <> 0
	BEGIN
		SELECT @PartyIds = ISNULL(STRING_AGG(CONVERT(VARCHAR(50), p.PartyID), ','), '')
		FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
			INNER JOIN bodb_licensee.dbo.Licensees la WITH(NOLOCK) ON p.OldRefID = la.LicenseeID
		    INNER JOIN DBOIC.bodb_OIC.dbo.Licensee l WITH(NOLOCK) ON l.RegisteredLicenseeName = la.LicenseeName AND l.PlatformId = @PlatformId
		WHERE p.PartyID IN (SELECT value FROM STRING_SPLIT(@PartyIds, ',')) 
	END

	-- Get agent list
	DECLARE @tblSite TABLE (Site VARCHAR(100), PartyID INT, BaseCurrency VARCHAR(12), BaseCurrencyID INT)
	INSERT INTO @tblSite (Site, PartyID, BaseCurrency, BaseCurrencyID)
	SELECT l.LicenseeName, p.PartyID, CASE WHEN e.ExchangeId = 142 THEN 'USDT' ELSE e.Code END, e.ExchangeId
	FROM dbo.Licensees l WITH (NOLOCK)
		INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON l.LicenseeId = p.OldRefId AND p.PartyType IN (1, 5)
		LEFT JOIN OAS_PartyBaseCurrency op WITH (NOLOCK) ON p.PartyID = op.PartyID AND op.FromDate <= @FromDate AND Op.ToDate >= @ToDate
		LEFT JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON e.ExchangeId = op.BaseCurrencyId 
	WHERE p.PartyId IN (SELECT CONVERT(INT, value) FROM STRING_SPLIT(@PartyIds, ','))

	IF EXISTS (SELECT TOP 1 1 FROM @tblSite WHERE  BaseCurrencyID IS NULL)
	BEGIN
		UPDATE t
		SET t.BaseCurrencyID = c.currency,
			t.BaseCurrency = CASE WHEN e.ExchangeId = 142 THEN 'USDT' ELSE e.Code END

		FROM @tblSite t
		INNER JOIN  DBCUST.bodb_licensee.dbo.LicenseeTransferCode l WITH(NOLOCK) ON t.Site = l.LicenseeName
		INNER JOIN bodb02.dbo.Customer c WITH(NOLOCK) ON l.CustID = c.CustID
		LEFT JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON e.ExchangeId = c.currency
		WHERE l.FromDate <= @FromDate AND l.ToDate >= @ToDate
		 
		DELETE FROM @tblSite WHERE BaseCurrencyID IS NULL
	END

	DECLARE @recommend TABLE (recommend INT, PartyID INT, BaseCurrency VARCHAR(12), BaseCurrencyID INT)
	INSERT INTO @recommend (recommend, PartyID, BaseCurrency, BaseCurrencyID)
	SELECT c.custid, t.PartyID, t.BaseCurrency, t.BaseCurrencyID
	FROM @tblSite t
		INNER JOIN bodb02.dbo.Dep_CustSuper s WITH (NOLOCK) ON t.Site = s.Site
		INNER JOIN bodb02.dbo.Customer c WITH (NOLOCK) ON s.custid = c.srecommend
	WHERE c.roleid = 2
		AND s.currency <> 20

	-- Get Exchange
	DEClARE @LA_BaseCurrency TABLE (CurrencyId INT, CurrencyName VARCHAR(12))
	INSERT INTO @LA_BaseCurrency(CurrencyId, CurrencyName)
	EXEC [LA_SelBaseCurrency]

	DECLARE @Exchange TABLE (ExchangeId INT, ExchangeDate SMALLDATETIME, Rate FLOAT, BaseCurrencyID INT, BaseCurrency VARCHAR(12), Code VARCHAR(65))
	DECLARE @bcurr VARCHAR(12), @bcID INT
	WHILE EXISTS (SELECT TOP 1 1 FROM @LA_BaseCurrency)
	BEGIN
		SELECT TOP 1 @bcurr = CurrencyName, @bcID = CurrencyId  FROM @LA_BaseCurrency

		INSERT INTO @Exchange (ExchangeId, ExchangeDate, Rate, BaseCurrencyID, BaseCurrency, Code)
		SELECT ExchangeId, ExchangeDate, BaseCurrencyRate, @bcID, @bcurr, Code
		FROM bodb02.dbo.LA_f_ExchangeDailySel (@FromDate, @ToDate, @bcurr)

		DELETE FROM @LA_BaseCurrency WHERE CurrencyId = @bcID
	END

	-- Get Product List
	DECLARE @ProductCodes VARCHAR(MAX)
	SELECT  @ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductPrefix FROM bodb_Licensee.dbo.Product3rd WITH (NOLOCK) WHERE ProductId NOT IN (3, 16, 25)
	SELECT  @ProductCodes = 'SB,' + @ProductCodes

	DECLARE @Products TABLE (GroupProductId INT, ProductId INT, ProductName VARCHAR(50), Sporttype INT, IsBA BIT)
	INSERT INTO @Products (GroupProductId, ProductId, ProductName, Sporttype, IsBA)
	SELECT 3, 3, 'BA', 0, 1
	UNION ALL SELECT 25, 25, 'Cashout', -1, 0
	UNION ALL
	SELECT DISTINCT ISNULL(g.GroupProductId, p.ProductId), ISNULL(g.ProductId, p.ProductId), ISNULL(g.ProductName, p.ProductName), f.SportType, 0 AS IsBA
	FROM bodb02.dbo.f_LicWinLoss_ProductSportType_Sel(@ProductCodes) f
		CROSS APPLY dbo.LA_f_Products3rd(f.ProductCode) p
		LEFT JOIN dbo.LA_f_GroupProduct(@ProductCodes,@FromDate,@ToDate) g ON p.ProductId = g.ProductId
	UNION  
	SELECT 74, 74, 'Player Tips', 157 , 0

	-- Get AmountToCompany data

	--#tmpNAPData_PT (WinlostDate, Currency, Bettype, apositiontaking, LicenseeWL, AmountToCompany, PartyID, BaseCurrencyID, ProductID)
	CREATE TABLE #tmpData_rptLicWinloss2 (
		WinlostDate		SMALLDATETIME, 
		Currency		INT, 
		Bettype			INT, 
		apositiontaking FLOAT, 
		winlost			MONEY,
		swinlost		MONEY,
		mwinlost		MONEY,
		awinlost		MONEY,
		scomm			MONEY,
		recommend		INT,
		IsBA			BIT,
		Sporttype		INT,
		PartyID INT, 
		BaseCurrencyID INT, 
		BaseCurrencuName VARCHAR(12)
	)

	CREATE CLUSTERED INDEX cix_#tmpData_rptLicWinloss2 ON #tmpData_rptLicWinloss2(recommend, WinlostDate, Currency)

	INSERT INTO #tmpData_rptLicWinloss2 (WinlostDate, Currency, Bettype, apositiontaking, winlost, swinlost,mwinlost,awinlost,scomm,recommend, IsBA, Sporttype, PartyID, BaseCurrencyID, BaseCurrencuName)
		SELECT b.WinlostDate, 
			   b.Currency,
			   b.bettype,
			   b.apositiontaking,
			   SUM(ISNULL(winlost,0)) winlost,
			   SUM(ISNULL(swinlost,0)) swinlost,
			   SUM(ISNULL(mwinlost,0)) mwinlost,
			   SUM(ISNULL(awinlost,0)) awinlost,
			   SUM(ISNULL(scomm,0)) scomm,
			   b.recommend,
			   b.isBA,
			   b.sporttype,
			   r.PartyID,
			   r.BaseCurrencyID,
			   r.BaseCurrency
	FROM bodb_LicenseeReport.dbo.rptLicWinloss2 b WITH (NOLOCK)
		INNER JOIN @recommend r ON b.recommend = r.recommend
	WHERE b.WinlostDate BETWEEN @FromDate AND @ToDate
		AND b.roleId = 2
		AND b.statusId IN (111, 112, 113, 114, 115)
	GROUP BY b.WinlostDate, 
			b.Currency,
			b.bettype,
			b.recommend,
			b.apositiontaking,
			 b.isBA,
			 b.sporttype,
			 r.PartyID,
			 r.BaseCurrencyID,
			 r.BaseCurrency

	CREATE TABLE #tmpData (WinlostDate SMALLDATETIME, Currency INT, Sporttype INT, Bettype INT, IsBA BIT, AmountToCompany MONEY, PartyID INT, BaseCurrencyID INT, BaseCurrencuName VARCHAR(12))
	INSERT INTO #tmpData (WinlostDate, Currency, Sporttype, Bettype, IsBA, AmountToCompany, PartyID, BaseCurrencyID, BaseCurrencuName)
	SELECT b.WinlostDate, b.Currency
		,CASE WHEN b.bettype IN (911, 912, 913, 914) THEN -1 ELSE b.sporttype END
		,CASE WHEN b.bettype = 17005 THEN b.bettype ELSE 0 END
		,b.isBA
		,-SUM(ISNULL(b.swinlost, 0) + ISNULL(b.mwinlost, 0) + ISNULL(b.awinlost, 0) + ISNULL(b.winlost, 0) + ISNULL(b.scomm, 0)) AS AmountToCompany
		,b.PartyID
		,b.BaseCurrencyID
		,b.BaseCurrencuName
	FROM #tmpData_rptLicWinloss2 b
	WHERE b.bettype NOT IN (901, 902, 911, 912)
	GROUP BY b.recommend, b.WinlostDate, b.Currency
		,CASE WHEN b.bettype IN (911, 912, 913, 914) THEN -1 ELSE b.sporttype END
		,CASE WHEN b.bettype = 17005 THEN b.bettype ELSE 0 END
		,b.isBA 
		,b.PartyID
		,b.BaseCurrencyID
		,b.BaseCurrencuName

	-- Return data
	-- Note: Saba promotion treat ProductId is max, always on bottom

	CREATE TABLE #NAP_Data (ProductID INT, ProductName VARCHAR(200), AmountToCompany MONEY, PartyID INT, CurrencyName VARCHAR(12), BaseCurrencyID INT)

	INSERT INTO #NAP_Data (ProductID, ProductName, AmountToCompany, PartyID, CurrencyName, BaseCurrencyID)
	SELECT CONVERT(INT, CASE WHEN t.Bettype = 17005 THEN 1001 WHEN p.ProductId = 37 THEN 1000 WHEN p.ProductId = 74 THEN 1002 ELSE p.ProductId END) AS ProductId
		,CONVERT(VARCHAR(50), CASE WHEN t.Bettype = 17005 THEN 'Sponsorship' ELSE p.ProductName END) AS ProductName
		,t.AmountToCompany, t.PartyID, t.BaseCurrencuName, t.BaseCurrencyID
	FROM (
		SELECT p.GroupProductId, t.Bettype, CONVERT(MONEY, SUM(-t.AmountToCompany * e.Rate)) AS AmountToCompany, t.PartyID, t.BaseCurrencuName, t.BaseCurrencyID
		FROM #tmpData t
			INNER JOIN @Products p ON t.Sporttype = p.Sporttype AND t.IsBA = p.IsBA
			INNER JOIN @Exchange e ON t.Currency = e.ExchangeId AND t.WinlostDate = e.ExchangeDate AND t.BaseCurrencyID = e.BaseCurrencyID
		GROUP BY p.GroupProductId, t.Bettype, t.PartyID, t.BaseCurrencuName, t.BaseCurrencyID
	) t
		INNER JOIN (SELECT DISTINCT ProductId, ProductName FROM @Products) p ON t.GroupProductId = p.ProductId

	-- Calculate LA data
	-- Get Product List
	DECLARE @ProductList TABLE (ProductId INT, ProductCode VARCHAR(50), ProductName VARCHAR(50))
	INSERT INTO @ProductList (ProductId, ProductCode, ProductName)
	SELECT ProductId, ProductPrefix, ProductName FROM dbo.Product3rd WITH (NOLOCK) WHERE ProductId <> 16 AND (EndOfSupportDate IS NULL OR EndOfSupportDate >= @FromDate) AND OfferSite IN (0, 2) -- Deposit only
	UNION ALL SELECT 0, 'SB', 'Sportsbook'

	DECLARE @LA_ProductCodes VARCHAR(MAX), @PartyIds_run VARCHAR(MAX)
	SELECT  @LA_ProductCodes = COALESCE(@LA_ProductCodes + ',', '') + ProductCode FROM @ProductList

	DECLARE @Result TABLE
	(
		PartyId INT, ProductId INT, LicensingFeeTypeId SMALLINT, GrossLicensingFee MONEY, LicensingFee MONEY, ExtraAmount MONEY, IsChargedByGroupMinFee BIT, IsChargedByMinFee BIT
		,Discount MONEY, DiscountRate MONEY, DiscountRemark NVARCHAR(4000), Rebate MONEY, RebateRate MONEY, RebateRemark NVARCHAR(4000), ExtraInfo NVARCHAR(4000)
	)

	DECLARE @FinalResult TABLE (PartyId INT, ProductId INT, AmountToCompany MONEY, LicensingFee MONEY, Discount MONEY, Rebate MONEY, Promotion MONEY, Sponsorship MONEY, ContributionDiscount MONEY, BetCount INT, OddsSpreadCost MONEY, PlayerTips MONEY)
	CREATE TABLE #LA_Data (PartyID INT, ProductName VARCHAR(200), ProductID INT, CurrencyName VARCHAR(12), AmountToCompany MONEY , BaseCurrencyID INT, OddsSpreadCost MONEY)

	-- refill data
	INSERT INTO @LA_BaseCurrency(CurrencyId, CurrencyName)
	EXEC [LA_SelBaseCurrency]

	WHILE EXISTS (SELECt TOP 1 1 FROM @LA_BaseCurrency)
	BEGIN
		SELECT TOP 1 @bcurr = CurrencyName, @bcID = CurrencyId  FROM @LA_BaseCurrency
		DELETE FROM @Result
		DELETE FROM @FinalResult

		SELECT @PartyIds_run = STRING_AGG(CAST(PartyID AS VARCHAR(50)),',') FROM @tblSite WHERE BaseCurrencyID = @bcID

		INSERT INTO @Result
		(
			PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
			,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark, ExtraInfo
		)
		EXEC dbo.LA_AmountToCompanyByProduct
			@PartyIds = @PartyIds_run
			,@ProductCodes = @LA_ProductCodes
			,@FromDate = @FromDate
			,@ToDate = @ToDate
			,@LicensingFeeTypeIds = '0,7,8,9' -- 7 = ContributionDiscount, 8 = BetCount, 9 = OddsSpeadAdjustment
			,@BaseCurrencyName = @bcurr


		INSERT INTO @FinalResult (PartyId, ProductId, AmountToCompany, LicensingFee, Discount, Rebate, Promotion, Sponsorship, ContributionDiscount, BetCount, OddsSpreadCost, PlayerTips)
		SELECT r.PartyId, r.ProductId, r.GrossLicensingFee, r.LicensingFee + r.ExtraAmount, r.Discount, r.Rebate, ISNULL(t.Promotion, 0), ISNULL(t.Sponsorship, 0), ISNULL(t.ContributionDiscount, 0), ISNULL(t.BetCount, 0), ISNULL(t.OddsSpreadAdjustment, 0), ISNULL(t.PlayerTips,0)
		FROM @Result r
			LEFT JOIN (
				SELECT PartyId, CASE WHEN ProductId IN (37, 74) THEN 0 ELSE ProductId END AS ProductId
					,SUM(CASE WHEN ProductId = 37 AND LicensingFeeTypeId = 0 THEN LicensingFee ELSE 0 END) AS Promotion
					,SUM(CASE WHEN ProductId = 37 AND LicensingFeeTypeId = 0 THEN ExtraAmount ELSE 0 END) AS Sponsorship
					,SUM(CASE WHEN LicensingFeeTypeId = 7 THEN ExtraAmount ELSE 0 END) AS ContributionDiscount
					,SUM(CASE WHEN LicensingFeeTypeId = 8 THEN ExtraAmount ELSE 0 END) AS BetCount
					,SUM(CASE WHEN LicensingFeeTypeId = 9 AND ExtraAmount < 0 THEN -ExtraAmount ELSE 0 END) AS OddsSpreadAdjustment
					,SUM(CASE WHEN ProductId = 74 AND LicensingFeeTypeId = 0 THEN -ExtraAmount ELSE 0 END) AS PlayerTips -- Recon Show Negative value
				FROM @Result
				WHERE ProductId IN (37,74) OR LicensingFeeTypeId > 0
				GROUP BY PartyId,CASE WHEN ProductId IN (37, 74) THEN 0 ELSE ProductId END
			) t ON r.PartyId = t.PartyId AND r.ProductId = t.ProductId
		WHERE r.LicensingFeeTypeId = 0 AND r.ProductId NOT IN (37, 74)

		INSERT INTO #LA_Data (PartyID, ProductName, ProductID, CurrencyName, AmountToCompany, BaseCurrencyID, OddsSpreadCost)
		SELECT r.PartyId, p.ProductName, p.ProductId, UPPER(@bcurr) AS CurrencyName, SUM(r.AmountToCompany) AS AmountToCompany, @bcID, SUM(r.OddsSpreadCost)
		FROM @FinalResult r
			INNER JOIN @ProductList p ON r.ProductId = p.ProductId
		GROUP BY r.PartyId, p.ProductName, p.ProductId

		DELETE FROM @LA_BaseCurrency WHERE CurrencyId = @bcID
	END


	CREATE TABLE #diff_summary(
			PartyID INT, 
			ProductName VARCHAR(50), 
			ProductID INT, 
			BaseCurrencyID	INT,
			CurrencyName VARCHAR(12), 
			LA_Amt MONEY, 
			NAP_Amt MONEY, 
			Diff_amt MONEY
			)

	INSERT INTO #diff_summary(PartyID, ProductName, ProductID, CurrencyName, LA_Amt, NAP_Amt, Diff_amt, BaseCurrencyID)
	SELECT	ISNULL(l.PartyID, n.PartyID) AS PartyID, 
			ISNULL(l.ProductName,n.ProductName) ProductName, 
			ISNULL(l.ProductID,n.ProductID) ProductID, 
			ISNULL(l.CurrencyName, n.CurrencyName) CurrencyName,
			ISNULL(l.AmountToCompany,0) AS  LA_Amt,
			ISNULL(n.AmountToCompany,0) AS NAP_Amt,
			- (ISNULL(l.AmountToCompany,0)- ISNULL(l.OddsSpreadCost,0)) - ISNULL(n.AmountToCompany,0) AS Diff_amt,
			ISNULL(l.BaseCurrencyID, n.BaseCurrencyID) BaseCurrencyID
	FROM #LA_Data l
	FULL JOIN #NAP_Data n ON l.PartyID = n.PartyID AND l.ProductID = n.ProductID 
	WHERE ABS(- (ISNULL(l.AmountToCompany,0)- ISNULL(l.OddsSpreadCost,0)) - ISNULL(n.AmountToCompany,0)) > 1.
	ORDER BY ISNULL(l.PartyID, n.PartyID), ISNULL(l.ProductID,n.ProductID)

	-- Diff by Adjustment
	BEGIN
		IF EXISTS (SELECT TOP 1 1 FROM #diff_summary WHERE ProductID IN (10,31))
		BEGIN
			DECLARE @BalanceUpDay SMALLDATETIME, @MoveBetsDay SMALLDATETIME, @ExchangeTerm_CutOffDate SMALLDATETIME, @PartyIds_adj VARCHAR(MAX)
			DECLARE @BettypeList_Adj TABLE (Bettype SMALLINT)
			DECLARE @ProductCodeList_Adj TABLE (ProductCode VARCHAR(10))
			DECLARE @tblSite_adj TABLE (SiteId INT, Site VARCHAR(100), PartyID INT, BaseCurrrencyID INT)

			DECLARE @MBBU TABLE (BalanceUpDay SMALLDATETIME, MoveBetsDay SMALLDATETIME)
			INSERT INTO @MBBU (BalanceUpDay, MoveBetsDay)
			EXEC bodb02.dbo.Age_SelBalanceUpDay

			SELECT @BalanceUpDay = BalanceUpDay, @MoveBetsDay = MoveBetsDay FROM @MBBU

			SELECT @ExchangeTerm_CutOffDate = f.CutoffDate FROM dbo.LA_f_GetCutOffDate() f WHERE f.TypeName = 'ExchangeTerms'

			-- Get adj parties 
			; WITH t AS 
			(
				SELECT DISTINCT PartyId FROM #diff_summary WHERE ProductID IN (10,31)
			)
			SELECT @PartyIds_adj  =  STRING_AGG(PartyId,',') 
			FROM t

			IF EXISTS( SELECT TOP 1 1 FROM #diff_summary WHERE ProductID = 10)
			BEGIN
				INSERT INTO @BettypeList_Adj VALUES (1800)
				INSERT INTO @ProductCodeList_Adj VALUES ('AGC')
			END
			IF EXISTS( SELECT TOP 1 1 FROM #diff_summary WHERE ProductID = 31)
			BEGIN
				INSERT INTO @BettypeList_Adj VALUES (8000)
				INSERT INTO @ProductCodeList_Adj VALUES ('BX')
			END

			-- @tblSite_adj
			INSERT INTO @tblSite_adj (SiteId, Site, PartyID, BaseCurrrencyID)
			SELECT l.LicenseeId, l.LicenseeName, p.PartyID, ts.BaseCurrencyID
			FROM bodb_Licensee.dbo.Licensees l WITH (NOLOCK)
				INNER JOIN bodb_Licensee.dbo.OAS_Party p WITH (NOLOCK) ON l.LicenseeId = p.OldRefId AND p.PartyType IN (1, 5)
				LEFT JOIN @tblSite ts ON ts.PartyID = p.PartyID
			WHERE p.PartyId IN (SELECT DISTINCT d.PartyID FROM #diff_summary d WHERE ProductID IN (10,31))

			-- I. LA ChargeRate
			BEGIN
				DECLARE @ChargeRate TABLE (ChargeId INT, FromDate SMALLDATETIME, ToDate SMALLDATETIME, Rate FLOAT, ProductID INT, PartyID INT)
				INSERT INTO @ChargeRate (ChargeId, FromDate, ToDate, Rate, ProductID, PartyID)
				SELECT  x.ChargeId, x.FromDate, x.ToDate, x.DI_Rate, x.ProductID, x.PartyID
				FROM @ProductCodeList_Adj adj
				CROSS APPLY(
					SELECT ChargeId, FromDate, ToDate, DI_Rate, ProductID, PartyID
					FROM dbo.LA_f_ChargeInfo (@PartyIds_adj, @FromDate, @ToDate, adj.ProductCode, 'OA', 1)
				) x

				-- ChargeRate by Currency
				DECLARE @ChargeRateByCurrency TABLE (ChargeId INT, Currency INT, Rate FLOAT)
				INSERT INTO @ChargeRateByCurrency (ChargeId, Currency, Rate)
				SELECT bc.ChargeId, bc.CurrencyId, bc.Rate
				FROM dbo.LA_ChargeRateByCurrency bc WITH (NOLOCK)
					INNER JOIN @ChargeRate c ON bc.ChargeId = c.ChargeId

				CREATE TABLE #tmpLAData (winlostdate SMALLDATETIME, Currency INT, MemberWL MONEY, Comm MONEY, Pcomm MONEY, PartyID INT, ProductID INT, BaseCurrencyID INT)
				INSERT INTO #tmpLAData (winlostdate, Currency, MemberWL, Comm, Pcomm, PartyID, ProductID, BaseCurrencyID)
				SELECT r.rptDate, r.CurrencyId
					,SUM(r.MemberWL) AS MemberWL
					,SUM(r.CommissionA + r.CommissionP) AS Comm
					,SUM(r.CommissionP)  Pcomm
					,s.PartyID
					,r.ProductID
					,s.BaseCurrrencyID
				FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct r WITH (NOLOCK)
					INNER JOIN @tblSite_adj s ON r.SiteId = s.SiteId
				WHERE r.rptDate BETWEEN @FromDate AND @ToDate
					AND r.ProductId IN (10,31)
					AND r.StatusId NOT IN (-1, 101, 102, 103)
					AND r.CustomerCategory NOT IN (27, 28)
					AND r.CurrencyId <> 20
				GROUP BY r.rptDate, r.CurrencyId, r.ProductID, s.PartyID, s.BaseCurrrencyID
			END

			-- NAP adj
			BEGIN
				DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME
				DECLARE @tblCustId TABLE (CustId INT, PartyID INT, BaseCurrencyID INT)
				INSERT INTO @tblCustId (CustId, PartyID, BaseCurrencyID)
				SELECT c.CustId, s.PartyID, s.BaseCurrrencyID
				FROM @tblSite_adj s
					INNER JOIN bodb02.dbo.Customer m WITH (NOLOCK) ON s.Site = m.Site AND m.roleid = 3
					INNER JOIN bodb02.dbo.customer c WITH (NOLOCK) ON m.custid = c.mrecommend AND c.roleid = 1
				WHERE m.username LIKE '%Acc%'
					AND c.username LIKE '%Dummy3rd%'
					AND m.currency <> 20

				-- Get data
				CREATE TABLE #tmpNAPData (
					winlostdate			SMALLDATETIME, 
					actual_winlostdate	SMALLDATETIME, 
					currency			INT, 
					transdesc			NVARCHAR(1000), 
					AmountToCompany		MONEY, 
					ProductID			INT, 
					PartyID				INT,
					BaseCurrencyID		INT
				)

				CREATE TABLE #tmpNAPData_bk (
					winlostdate			SMALLDATETIME, 
					actual_winlostdate	SMALLDATETIME, 
					currency			INT, 
					transdesc			NVARCHAR(1000), 
					AmountToCompany		MONEY, 
					ProductID			INT, 
					CustID				INT
				)

				IF @ToDate > @MoveBetsDay
				BEGIN
					SELECT @FDate = CASE WHEN @FromDate <= @MoveBetsDay THEN DATEADD(DAY, 1, @MoveBetsDay) ELSE @FromDate END
						,@TDate = @ToDate
		
					INSERT INTO #tmpNAPData (winlostdate, currency, transdesc, AmountToCompany, ProductID, PartyID, BaseCurrencyID)
					SELECT b.winlostdate, b.currency, b.transdesc, SUM(swinlost + mwinlost + awinlost + winlost - actual_stake + scomm),
						  CASE WHEN b.bettype = 1800 THEN 10 ELSE 31 END ProductID, c.PartyID, c.BaseCurrencyID
					FROM bodb02.dbo.bettrans b WITH (NOLOCK)
						INNER JOIN @tblCustId c ON b.custid = c.CustId
					WHERE b.winlostdate BETWEEN @FDate AND @TDate
						AND b.currency <> 20
						AND b.statusId IN (111, 112, 113)
						AND b.bettype IN (SELECT z.bettype FROM @BettypeList_Adj z)
					GROUP BY b.winlostdate, b.currency, b.transdesc, CASE WHEN b.bettype = 1800 THEN 10 ELSE 31 END, c.PartyID, c.BaseCurrencyID
				END

				IF @FromDate <= @MoveBetsDay AND @ToDate >= @BalanceUpDay
				BEGIN
					SELECT @FDate = CASE WHEN @FromDate < @BalanceUpDay THEN @BalanceUpDay ELSE @FromDate END
						,@TDate = CASE WHEN @ToDate > @MoveBetsDay THEN @MoveBetsDay ELSE @ToDate END

					INSERT INTO #tmpNAPData (winlostdate, currency, transdesc, AmountToCompany, ProductID, PartyID, BaseCurrencyID)
					SELECT b.winlostdate, b.currency, b.transdesc, SUM(swinlost + mwinlost + awinlost + winlost - actual_stake + scomm),
							CASE WHEN b.bettype = 1800 THEN 10 ELSE 31 END ProductID, c.PartyID, c.BaseCurrencyID
					FROM bodb02.dbo.bettrans14 b WITH (NOLOCK)
						INNER JOIN @tblCustId c ON b.custid = c.CustId
					WHERE b.winlostdate BETWEEN @FDate AND @TDate
						AND b.currency <> 20
						AND b.statusId IN (111, 112, 113)
						AND b.bettype IN (SELECT z.bettype FROM @BettypeList_Adj z)
					GROUP BY b.winlostdate, b.currency, b.transdesc, CASE WHEN b.bettype = 1800 THEN 10 ELSE 31 END, c.PartyID, c.BaseCurrencyID
				END

				IF @FromDate < @BalanceUpDay
				BEGIN
					SELECT @FDate = @FromDate
						,@TDate = CASE WHEN @ToDate >= @BalanceUpDay THEN DATEADD(DAY, -1, @BalanceUpDay) ELSE @ToDate END

					DECLARE @CustIds VARCHAR(MAX), @SQL VARCHAR(MAX), @Bettype_Adjs VARCHAR(50)

					SELECT @Bettype_Adjs = STRING_AGG(Bettype,',') FROM @BettypeList_Adj

					SELECT @CustIds = COALESCE(@CustIds + ',', '') + CONVERT(VARCHAR(20), CustId) FROM @tblCustId
					SET @SQL = 'SELECT winlostdate, currency, transdesc, AmountToCompany, ProductID, CustID
								FROM OPENQUERY(DBARC, ''SELECT winlostdate, currency, transdesc, SUM(swinlost + mwinlost + awinlost + winlost - actual_stake + scomm) AS AmountToCompany, CustID,
															   CASE WHEN bettype = 1800 THEN 10 ELSE 31 END ProductID
														FROM bodb_Archive.dbo.bettrans_bk WITH (NOLOCK)
														WHERE winlostdate BETWEEN ''''' + CONVERT(VARCHAR(10), @FDate, 120) + ''''' AND ''''' + CONVERT(VARCHAR(10), @TDate, 120) + '''''
															AND custid IN (' + @CustIds + ')
															AND currency <> 20
															AND statusId IN (111, 112, 113)
															AND bettype IN (' + @Bettype_Adjs + ')
														GROUP BY winlostdate, currency, transdesc, CustID, CASE WHEN bettype = 1800 THEN 10 ELSE 31 END, CustID'')'

					INSERT INTO #tmpNAPData_bk (winlostdate, currency, transdesc, AmountToCompany, ProductID, CustID)
					EXEC (@SQL)

					INSERT INTO #tmpNAPData (winlostdate, currency, transdesc, AmountToCompany, ProductID, PartyID, BaseCurrencyID)
					SELECT b.winlostdate, b.currency, b.transdesc, SUM(b.AmountToCompany),b.ProductID, c.PartyID, c.BaseCurrencyID
					FROM #tmpNAPData_bk b
						INNER JOIN @tblCustId c ON b.custid = c.CustId
					GROUP BY b.winlostdate, b.currency, b.transdesc, b.ProductID, c.PartyID, c.BaseCurrencyID

				END

				-- update winlostdate of adjustment ticket
				UPDATE #tmpNAPData
				SET actual_winlostdate = CASE WHEN transdesc LIKE '%Adjustment - Date:%' THEN SUBSTRING(transdesc, CHARINDEX('Date: ', transdesc, 0) + 6, 10) ELSE winlostdate END

			END

			DECLARE @Result_adj TABLE (
					PartyID					INT, 
					ProductID				INT, 
					BaseCurrencyID			INT ,
					Func					VARCHAR(10), 
					Currency				VARCHAR(12), 
					[Type]					VARCHAR(200), 
					AmountToCompany			MONEY, 
					ExRate					FLOAT, 
					BasedAmountToCompany	MONEY,
					Remark					VARCHAR(4000)
				)
			-- LA
			INSERT INTO @Result_adj (PartyID, ProductID, BaseCurrencyID, Func, Currency, [Type], ExRate, AmountToCompany, BasedAmountToCompany)
			SELECT d.PartyID, d.ProductID, d.BaseCurrencyID, 'LA', NULL Currency, 'Actual Bet', NULL ExRate
				,SUM(CASE WHEN d.ProductId = 31 AND @FromDate >= @ExchangeTerm_CutOffDate THEN (d.MemberWL + d.Pcomm) * ISNULL(bc.Rate, c.Rate)  ELSE d.MemberWL * ISNULL(bc.Rate, c.Rate) + d.Comm END) AS AmountToCompany
				,SUM(CASE WHEN d.ProductId = 31 AND @FromDate >= @ExchangeTerm_CutOffDate THEN (d.MemberWL + d.Pcomm) * ISNULL(bc.Rate, c.Rate) ELSE (d.MemberWL * ISNULL(bc.Rate, c.Rate) + d.Comm) END  * e.Rate) AS BasedAmountToCompany
			FROM #tmpLAData d
				INNER JOIN @Exchange e ON d.Currency = e.ExchangeId AND d.winlostdate = e.ExchangeDate AND e.BaseCurrencyID = d.BaseCurrencyID
				INNER JOIN @ChargeRate c ON d.winlostdate BETWEEN c.FromDate AND c.ToDate AND d.ProductID = c.ProductID AND c.PartyID = d.PartyID
				LEFT JOIN @ChargeRateByCurrency bc ON c.ChargeId = bc.ChargeId AND d.Currency = bc.Currency
			GROUP BY d.PartyID, d.ProductID, d.BaseCurrencyID

			-- NAP
			INSERT INTO @Result_adj (PartyID, ProductID, BaseCurrencyID, Func, Currency, [Type], ExRate, AmountToCompany, BasedAmountToCompany)
			SELECT d.PartyID, d.ProductID, d.BaseCurrencyID, 'NAP', NULL Currency
				,CASE WHEN actual_winlostdate BETWEEN @FromDate AND @ToDate THEN 'Actual Bet' ELSE 'Adjustment without this month' END AS [Type]
				,NULL AS ExRate
				,SUM(d.AmountToCompany) AS AmountToCompany
				,SUM(d.AmountToCompany * e.Rate) AS BasedAmountToCompany
			FROM #tmpNAPData d
				INNER JOIN @Exchange e ON d.Currency = e.ExchangeId AND d.winlostdate = e.ExchangeDate AND e.BaseCurrencyID = d.BaseCurrencyID
			GROUP BY
				--e.Code
				CASE WHEN actual_winlostdate BETWEEN @FromDate AND @ToDate THEN 'Actual Bet' ELSE 'Adjustment without this month' END
				--,e.Rate
				,d.PartyID, d.ProductID, d.BaseCurrencyID

			UPDATE t
			SET t.Remark = u.Remark
			FROM @Result_adj t
			CROSS APPLY (
				SELECT STRING_AGG(CHAR(9) + CHAR(9) + FORMAT(u.winlostdate,'MMM dd, yyyy') + ': Adjustment for transaction on ' + FORMAT(u.actual_winlostdate,'MMM dd, yyyy'), CHAR(13)) Remark
				FROM (		
							SELECT DISTINCT  u.winlostdate, u.actual_winlostdate
							FROM	#tmpNAPData u
							WHERE t.PartyID = u.PartyID AND t.ProductID = u.ProductID AND t.BaseCurrencyID = u.BaseCurrencyID
							AND u.actual_winlostdate NOT BETWEEN @FromDate AND @ToDate
					)u
			) u
			WHERE t.[Type] = 'Adjustment without this month'

			DROP TABLE #tmpNAPData
			DROP TABLE #tmpNAPData_bk
			DROP TABLE #tmpLAData
		END

	END

	-- Diff by PT
	BEGIN
		DECLARE @Products_PT TABLE (GroupProductId INT, ProductId INT, ProductCode VARCHAR(20))
		INSERT INTO @Products_PT (GroupProductId, ProductId, ProductCode)
		SELECT GroupProductId, ProductId, ProductCode
		FROM dbo.LA_f_GroupProduct('',@FromDate,@ToDate)
		WHERE GroupProductId IN (SELECT DISTINCT z.ProductID FROM #diff_summary z)

		DECLARE @ProductCode_PT VARCHAR(MAX), @PartyIDs_PT  VARCHAR(MAX)
		SELECT  @ProductCode_PT = COALESCE(@ProductCode_PT + ',', '') + ProductCode FROM @Products_PT

		-- Get adj parties 
		; WITH t AS 
		(
			SELECT DISTINCT PartyId FROM #diff_summary
		)
		SELECT @PartyIDs_PT  =  STRING_AGG(PartyId,',') 
		FROM t

		DECLARE @tblSite_PT TABLE (SiteId INT, Site VARCHAR(100), PartyID INT, BaseCurrencyID INT)
		INSERT INTO @tblSite_PT (SiteId, Site, PartyID, BaseCurrencyID)
		SELECT l.LicenseeId, l.LicenseeName, p.PartyID, ts.BaseCurrencyID
		FROM dbo.Licensees l WITH (NOLOCK)
			INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON l.LicenseeId = p.OldRefId AND p.PartyType IN (1, 5)
			LEFT JOIN @tblSite ts ON p.PartyID = ts.PartyID
		WHERE p.PartyId IN (SELECT DISTINCT z.PartyID FROM #diff_summary z)

		DECLARE @Bettype TABLE (Bettype INT, TypeId TINYINT)
		INSERT INTO @Bettype (Bettype, TypeId)
		SELECT DiSTINCT x.bettype, 
						CASE WHEN x.SubProduct IN ('Jackpot Contribution') THEN 1
							 WHEN x.SubProduct IN ('Prize','Lucky Draw','Bonus','Promotion') THEN 2
							 WHEN x.SubProduct IN ('Jackpot Prize') THEN 3
							 WHEN x.SubProduct IN ('Odds Spread Adjustment') THEN 4 END  TypeId
		FROM bodb02.dbo.SportBettypeMatrix x WITH(NOLOCK)
		WHERE x.SubProduct IN ('Jackpot Contribution','Jackpot Prize','Prize','Lucky Draw','Bonus','Odds Spread Adjustment','Promotion')

		INSERT INTO @Bettype (Bettype, TypeId)
		SELECT s.Bettype, 2 AS TypeId -- Promotion (include Free bets)
		FROM (
			SELECT DISTINCT Bettype
			FROM bodb02.dbo.SportBettypeMatrix WITH (NOLOCK)
			WHERE SportType IN (150, 173)
		) s
			LEFT JOIN @Bettype b ON s.BetType = b.Bettype
		WHERE b.Bettype IS NULL

		-- LA chargeRate
		BEGIN
			DECLARE @ChargeInfo TABLE (ChargeId INT, ChargeType TINYINT, PartyId INT, LicenseeId INT, Bettype INT, FromDate SMALLDATETIME, ToDate SMALLDATETIME, Rate FLOAT, ProductID INT)
			INSERT INTO @ChargeInfo (ChargeId, ChargeType, PartyId, LicenseeId, FromDate, ToDate, Rate, Bettype, ProductID)
			SELECT DISTINCT ChargeId, ChargeType, PartyId, LicenseeId, FromDate, ToDate, DI_Rate AS Rate
				,CASE
					WHEN ProductId = 11 AND ChargeType = 12 THEN 1706 -- GD Tip
					WHEN ProductId = 39 AND ChargeType = 12 THEN 3007 -- SA Tip
					ELSE Bettype END
				, ProductID
			FROM dbo.LA_f_ChargeInfo (@PartyIDs_PT, @FromDate, @ToDate, @ProductCode_PT, 'OA', 1)
			WHERE DI_Rate > 0

			-- Get Winloss data
			CREATE TABLE #tmpLAData_PT (
				WinlostDate		SMALLDATETIME, 
				Currency		INT, 
				SiteId			INT, 
				Bettype			INT, 
				LicenseeWL		MONEY, 
				Contribution	MONEY, 
				Promotion		MONEY, 
				JackpotPrize	MONEY, 
				OddsSpread		MONEY,
				PartyID			INT,
				BaseCurrencyID	INT,
				ProductID		INT
			)
			INSERT INTO #tmpLAData_PT (WinlostDate, Currency, SiteId, Bettype, LicenseeWL, Contribution, Promotion, JackpotPrize, OddsSpread, PartyID, BaseCurrencyID, ProductID)
			SELECT r.rptDate, r.CurrencyId, r.SiteId
				,CASE WHEN r.Bettype IN (1706, 3007) THEN r.Bettype ELSE ISNULL(sbr.BettypeRef, -1) END AS Bettype
				,SUM(CASE WHEN b.Bettype IS NOT NULL OR r.TicketType = 2 THEN 0 ELSE -ISNULL(r.MemberWL, 0) END) AS LicenseeWL
				,SUM(CASE WHEN b.TypeId = 1 THEN ISNULL(-r.GrossWL, 0) ELSE 0 END) AS Contribution
				,SUM(CASE WHEN b.TypeId = 2 OR r.TicketType = 2 THEN ISNULL(r.MemberWL, 0) ELSE 0 END) AS Promotion
				,SUM(CASE WHEN b.TypeId = 3 THEN ISNULL(r.MemberWL, 0) ELSE 0 END) AS JackpotPrize
				,SUM(CASE WHEN b.TypeId = 4 THEN ISNULL(-r.GrossWL, 0) ELSE 0 END) AS OddsSpread
				,s.PartyID
				,s.BaseCurrencyID
				,r.ProductID
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct r WITH (NOLOCK)
				INNER JOIN @tblSite_PT s ON r.SiteId = s.SiteId
				LEFT JOIN dbo.Sport_Bettype_Reference sbr WITH (NOLOCK) ON sbr.Bettype = r.Bettype
				LEFT JOIN @Bettype b ON b.Bettype = r.Bettype
			WHERE r.rptDate BETWEEN @FromDate AND @ToDate
				AND r.ProductId IN (SELECT p.ProductId FROM @Products p)
				AND r.StatusId NOT IN (-1, 101, 102, 103)
				AND r.CustomerCategory NOT IN (27, 28)
				AND r.CurrencyId <> 20
				AND r.ProductId <> 25 -- CO
			GROUP BY r.rptDate, r.CurrencyId, r.SiteId
				,CASE WHEN r.Bettype IN (1706, 3007) THEN r.Bettype ELSE ISNULL(sbr.BettypeRef, -1) END
				,s.PartyID
				,s.BaseCurrencyid
				,r.ProductID

		END

		-- NAP PT
		BEGIN
			-- Get agent list
			DECLARE @recommend_PT TABLE (recommend INT, PartyID INT, BaseCurrencyID INT)
			INSERT INTO @recommend_PT (recommend, PartyID, BaseCurrencyID )
			SELECT c.custid, t.PartyID, t.BaseCurrencyid
			FROM @tblSite_PT t
				INNER JOIN bodb02.dbo.Dep_CustSuper s WITH (NOLOCK) ON t.Site = s.Site
				INNER JOIN bodb02.dbo.Customer c WITH (NOLOCK) ON s.custid = c.srecommend
			WHERE c.roleid = 2
				AND s.currency <> 20

			-- Get AmountToCompany data
			CREATE TABLE #tmpNAPData_PT (
				WinlostDate		SMALLDATETIME, 
				Currency		INT, 
				Bettype			INT, 
				apositiontaking FLOAT, 
				LicenseeWL		MONEY, 
				AmountToCompany MONEY,
				PartyID			INT,
				BaseCurrencyID	INT,
				ProductID		INT
			)
			INSERT INTO #tmpNAPData_PT (WinlostDate, Currency, Bettype, apositiontaking, LicenseeWL, AmountToCompany, PartyID, BaseCurrencyID, ProductID)
			SELECT b.WinlostDate, b.Currency, b.Bettype, b.apositiontaking
				,-SUM(ISNULL(b.winlost, 0)) AS LicenseeWL
				,SUM(ISNULL(b.swinlost, 0) + ISNULL(b.mwinlost, 0) + ISNULL(b.awinlost, 0) + ISNULL(b.winlost, 0) + ISNULL(b.scomm, 0)) AS AmountToCompany
				, r.PartyID, r.BaseCurrencyID, f.ProductID
			FROM #tmpData_rptLicWinloss2 b WITH (NOLOCK)
				INNER JOIN @recommend_PT r ON b.recommend = r.recommend
				INNER JOIN (
					SELECT DISTINCT CONVERT(SMALLINT, t.SportType) AS SportType, CASE WHEN t.ProductID = 1THEN 0 ELSE p3d.Productid END Productid
					FROM bodb02.dbo.f_LicWinLoss_ProductSportType_Sel(@ProductCode_PT) t
					LEFT JOIN dbo.Product3rd p3d WITH(NOLOCK) ON t.ProductCode = p3d.ProductPrefix
				) f ON b.sporttype = f.SportType
			WHERE b.WinlostDate BETWEEN @FromDate AND @ToDate
				AND b.bettype NOT IN (901, 902, 903, 904, 911, 912, 913, 914)
				AND b.IsBA = 0
			GROUP BY b.recommend, b.WinlostDate, b.Currency, b.Bettype, b.apositiontaking, r.PartyID, r.BaseCurrencyID, f.ProductID 
	
		END

		DECLARE @Result_PT TABLE (
			Func					VARCHAR(10), 
			LicenseeWL				MONEY, 
			ChargeRate				SMALLMONEY, 
			LicensingFee			MONEY,
			Contribution			MONEY, 
			ContributionDiscount	MONEY, 
			Promotion				MONEY, 
			JackpotPrize			MONEY, 
			OddsSpread				MONEY, 
			IsShowOddsSpread		TINYINT,
			PartyID					INT,
			BaseCurrencyID			INT,
			ProductID				INT,
			firstday_PT				DATETIME,
			isSamePT				BIT DEFAULT 0
		)

		-- LA
		INSERT INTO @Result_PT (Func, LicenseeWL, ChargeRate, LicensingFee, Contribution, ContributionDiscount, Promotion, JackpotPrize, OddsSpread, IsShowOddsSpread,PartyID,BaseCurrencyID,ProductID,firstday_PT)
		SELECT 'LA', LicenseeWL, ChargeRate, LicensingFee, Contribution, ContributionDiscount, Promotion, JackpotPrize, OddsSpread, 1 AS IsShowOddsSpread,PartyID,BaseCurrencyID,ProductID,firstday_PT
		FROM (
			SELECT
				CONVERT(SMALLMONEY, ISNULL(bc.Rate, c.Rate)) AS ChargeRate
				,CONVERT(MONEY, SUM(t.LicenseeWL * e.Rate)) AS LicenseeWL
				,CONVERT(MONEY, SUM(-t.LicenseeWL * ISNULL(bc.Rate, c.Rate) * e.Rate)) AS LicensingFee
				,CONVERT(MONEY, SUM(t.Contribution * e.Rate)) AS Contribution
				,CONVERT(MONEY, SUM(t.Contribution * e.Rate * ISNULL(bc.Rate, c.Rate))) AS ContributionDiscount
				,CONVERT(MONEY, SUM(t.Promotion * e.Rate)) AS Promotion
				,CONVERT(MONEY, SUM(t.JackpotPrize * e.Rate)) AS JackpotPrize
				,CONVERT(MONEY, SUM(-t.OddsSpread * e.Rate)) AS OddsSpread
				,t.PartyID
				,t.BaseCurrencyID
				,t.ProductID
				,MIN(c.FromDate) firstday_PT
			FROM #tmpLAData_PT t
				INNER JOIN @Exchange e ON t.Currency = e.ExchangeId AND t.WinlostDate = e.ExchangeDate AND e.BaseCurrencyID = t.BaseCurrencyID
				INNER JOIN @ChargeInfo c ON t.SiteId = c.LicenseeId AND (t.Bettype = c.Bettype OR c.Bettype = -1) AND t.WinlostDate BETWEEN c.FromDate AND c.ToDate AND t.ProductID = c.ProductID
				LEFT JOIN dbo.LA_ChargeRateByCurrency bc WITH (NOLOCK) ON c.ChargeId = bc.ChargeId AND t.Currency = bc.CurrencyId
			GROUP BY CONVERT(SMALLMONEY, ISNULL(bc.Rate, c.Rate)),t.PartyID,t.BaseCurrencyID,t.ProductID
		) d
		
		UPDATE r
		SET r.OddsSpread = 0, r.IsShowOddsSpread = 0 
		FROM @Result_PT r 
		WHERE Func = 'LA' AND -OddsSpread <= 0

		-- NAP
		;WITH CTE_tmpData AS (
			SELECT
				CONVERT(INT, ISNULL(b.TypeId, 0)) AS TypeId
				,CONVERT(SMALLMONEY, ISNULL(1.0 - t.apositiontaking, 0)) AS HousePT
				,CONVERT(MONEY, SUM(t.LicenseeWL * e.Rate)) AS LicenseeWL
				,CONVERT(MONEY, SUM(t.AmountToCompany * e.Rate)) AS CompanyWL
				, t.PartyID
				, t.BaseCurrencyID
				, t.ProductID
				, MIN(WinlostDate) AS firstday_PT
			FROM #tmpNAPData_PT t
				INNER JOIN @Exchange e ON t.Currency = e.ExchangeId AND t.WinlostDate = e.ExchangeDate AND t.BaseCurrencyID = e.BaseCurrencyID
				LEFT JOIN @Bettype b ON t.Bettype = b.Bettype
			GROUP BY
				CONVERT(INT, ISNULL(b.TypeId, 0))
				,CONVERT(SMALLMONEY, ISNULL(1.0 - t.apositiontaking, 0))
				, t.PartyID
				, t.BaseCurrencyID
				, t.ProductID
		), CTE_Data AS (
			SELECT  PartyID, BaseCurrencyID, ProductID, TypeId, HousePT, LicenseeWL, CompanyWL, firstday_PT, ROW_NUMBER() OVER( PARTITION BY PartyID, BaseCurrencyID, ProductID ORDER BY TypeId) AS RN
			FROM CTE_tmpData
		)
		INSERT INTO @Result_PT (PartyID, BaseCurrencyID, ProductID,Func, LicenseeWL, ChargeRate, LicensingFee, Contribution, ContributionDiscount, Promotion, JackpotPrize, OddsSpread, IsShowOddsSpread, firstday_PT)
		SELECT d.PartyID, d.BaseCurrencyID, d.ProductID, 'NAP', ISNULL(d.LicenseeWL, 0), ISNULL(d.HousePT, 0), ISNULL(d.CompanyWL, 0)
			,ISNULL(t.Contribution, 0) AS Contribution
			,CONVERT(MONEY, 0) AS ContributionDiscount
			,ISNULL(t.Promotion, 0) AS Promotion
			,ISNULL(t.JackpotPrize, 0) AS JackpotPrize
			,ISNULL(t.OddsSpread, 0) AS OddsSpread
			,1 AS IsShowOddsSpread
			,d.firstday_PT
		FROM CTE_Data d
			FULL OUTER JOIN (
				SELECT PartyID, BaseCurrencyID, ProductID,
					 SUM(CASE WHEN TypeId = 1 THEN -CompanyWL ELSE 0 END) AS Contribution
					,SUM(CASE WHEN TypeId = 2 THEN CompanyWL ELSE 0 END) AS Promotion
					,SUM(CASE WHEN TypeId = 3 THEN CompanyWL ELSE 0 END) AS JackpotPrize
					,SUM(CASE WHEN TypeId = 4 THEN CompanyWL ELSE 0 END) AS OddsSpread
				FROM CTE_Data
				WHERE TypeId IS NOT NULL
				GROUP BY PartyID, BaseCurrencyID, ProductID
			) t ON d.TypeId = 0 AND d.RN = 1 AND d.PartyID = t.PartyID AND d.ProductID = t.ProductID AND d.BaseCurrencyID = t.BaseCurrencyID
		WHERE ISNULL(d.TypeId, 0) = 0

		UPDATE @Result_PT SET IsShowOddsSpread = 0 WHERE Func = 'NAP' AND OddsSpread = 0

		DROP TABLE #tmpLAData_PT
		DROP TABLE #tmpNAPData_PT

	END

	-- Final resut
	BEGIN
		DECLARE  @Remark_ChargeRate TABLE (PartyID INT, ProductID INT, BaseCurrencyID INT, Remark VARCHAR(4000) )
		DECLARE  @Remark_Adj TABLE (PartyID INT, ProductID INT, BaseCurrencyID INT, Remark VARCHAR(4000) , IsDiffActualBet BIT DEFAULT 0, IsHaveAdj BIT DEFAULT 0)

		;WITH t AS
		(
			SELECT Func, PartyID, ProductID, BaseCurrencyID, COUNT(DISTINCT ChargeRate) cnt, MIN(ChargeRate) minc, MAX(ChargeRate) maxc, MIN(firstday_PT) firstday_PT
			FROM @Result_PT
			GROUP BY Func, PartyID, ProductID, BaseCurrencyID
		), u AS
		(
			SELECT	ISNULL(t1.ProductID, t2.ProductID) ProductID, 
					ISNULL(t1.PartyID, t2.PartyID) PartyID, 
					ISNULL(t1.BaseCurrencyID, t2.BaseCurrencyID) BaseCurrencyID, 
					CASE WHEN t1.cnt <> t2.cnt THEN 0
					     WHEN t1.cnt = t2.cnt AND t1.maxc = t2.maxc AND t1.minc = t2.minc  AND t1.firstday_PT <= t2.firstday_PT THEN 1
						 ELSE 0 END IsSamePT
			FROM  t t1  FULL JOIN t t2 ON t2.Func = 'NAP' AND t1.ProductID = t2.ProductID AND t1.PartyID = t2.PartyID AND t1.BaseCurrencyID = t2.BaseCurrencyID
			WHERE t1.Func = 'LA'
		)
		UPDATE pt
		SET		pt.isSamePT = u.IsSamePT
		FROM    @Result_PT pt
		INNER JOIN u ON pt.ProductID = u.ProductID AND pt.PartyID = u.PartyID AND u.IsSamePT = 1 AND pt.BaseCurrencyID = u.BaseCurrencyID
		WHERE pt.ProductID NOT IN (0)

	
		; WITH  u_chargeRate AS
		(
			SELECT  Func, PartyID, ProductID, STRING_AGG(CAST(ChargeRate * 100 AS VARCHAR(10)) + '%', ', ') ChargeRate, firstday_PT, BaseCurrencyID
			FROM	@Result_PT
			WHERE   isSamePT = 0
			GROUP BY  Func,PartyID, ProductID, firstday_PT, BaseCurrencyID
		), z AS 
		(
			SELECT  uc.Func, uc.PartyID, uc.ProductID, uc.BaseCurrencyID,
						CASE WHEN uc.Func = 'NAP' THEN 'NAP:' + CHAR(13) ELSE 'LA:' + CHAR(13) END + STRING_AGG ( CASE WHEN uc.Func = 'NAP' THEN CHAR(9) + '- Having bet tickets with charge rate ' + ChargeRate + ' From ' + FORMAT(firstday_PT,'MMM dd, yyyy') 
						ELSE CHAR(9) +  '- Charge rate setting ' + ChargeRate + ' From ' + FORMAT(firstday_PT,'MMM dd, yyyy') END, CHAR(13)) AS Remark
			FROM	u_chargeRate uc
			GROUP BY  PartyID, ProductID, BaseCurrencyID, Func
		)
		INSERT INTO @Remark_ChargeRate (PartyID, ProductID, BaseCurrencyID, Remark)
		SELECT  d.PartyID, d.ProductID, d.BaseCurrencyID, STRING_AGG(Remark, CHAR(13)+CHAR(13))
		FROM 
		(
			SELECT PartyID, ProductID, BaseCurrencyID, 'Due to the differences on product charge rate or having tickets before launched date' + CHAR(13) + STRING_AGG(Remark, CHAR(13)) Remark
			FROM	z 
			GROUP BY PartyID, ProductID, BaseCurrencyID
		) d
		GROUP BY d.PartyID, d.ProductID, d.BaseCurrencyID

		; WITH t AS
		(
			SELECt PartyID, Func ,ProductID, BaseCurrencyID,  CASE WHEN Type = 'Actual Bet' THEN CHAR(9) + '- Actual bet this month: ' + FORMAT(BasedAmountToCompany,'N','en-us')
														ELSE CHAR(9) + '- Adjustment without this month: ' + FORMAT(BasedAmountToCompany,'N','en-us') + Char(13) + Remark  END Remark
			FROM @Result_adj
		), u AS
		(
		SELECT PartyID, ProductID, BaseCurrencyID, CASE WHEN Func = 'NAP' THEN 'NAP:' + CHAR(13) ELSE 'LA:' + ChAR(13) END +  STRING_AGG(Remark, CHAR(13))  Remark
		FROM t 
		GROUP BY PartyID, ProductID, BaseCurrencyID, Func
		)
		INSERT INTO @Remark_Adj (PartyID, ProductID, BaseCurrencyID, Remark)
		SELECT PartyID, ProductID, BaseCurrencyID , 'Due to adjustment' + CHAR(13) + STRING_AGG(Remark,CHAR(13)) Remark
		FROM u
		GROUP BY PartyID, ProductID, BaseCurrencyID

		-- Final result
		; WITH TotalDiffAmt AS
		(
			SELECT PartyID, BaseCurrencyID ,SUM(Diff_amt) Diff_amt
			FROM	#diff_summary 
			WHERE ProductID NOT IN ( 1000,1001,1002)
			GROUP BY PartyID, BaseCurrencyID
		)
		, TotalDiffAmt_Filter AS
		(
			SELECT PartyID, BaseCurrencyID
			FROM  TotalDiffAmt t
			WHERE (@FilterType_CNY = 0 AND @FilterType_EUR = 0)
				OR (
					t.BaseCurrencyID = 13 AND (  
												(@FilterType_CNY = 1 AND t.Diff_amt BETWEEN @MinValue_CNY AND @MaxValue_CNY)
													OR
												(@FilterType_CNY = 2 AND t.Diff_amt NOT BETWEEN @MinValue_CNY AND @MaxValue_CNY)
											   )
				)
				OR (
					t.BaseCurrencyID = 6 AND (
												(@FilterType_EUR = 1 AND t.Diff_amt BETWEEN @MinValue_EUR AND @MaxValue_EUR)
													OR
												(@FilterType_EUR = 2 AND t.Diff_amt NOT BETWEEN @MinValue_EUR AND @MaxValue_EUR)
											 )
				)
		)
		,t AS
		(
			SELECT ISNULL(ra.PartyID, rc.PartyID) PartyID, 
				   ISNULL(ra.ProductID, rc.ProductID) ProductID,
				   ISNULL(ra.BaseCurrencyID, rc.BaseCurrencyID)  BaseCurrencyID,
				  CASE WHEN ra.Remark IS NULL THEN ISNULL(rc.Remark,'') ELSE 
					CASE WHEN rc.Remark IS NULL THEN  ISNULL(ra.Remark,'') ELSE CONCAT(ra.Remark, CHAR(13) + CHAR(13), ISNULL(rc.Remark,'')) END  END Remark
			FROM @Remark_Adj ra 
			FULL JOIN @Remark_ChargeRate rc ON ra.PartyID = rc.PartyID AND ra.ProductID = rc.ProductID AND ra.BaseCurrencyID = rc.BaseCurrencyID
		)
		SELECt t.PartyID,
			   op.PartyName, 
			   t.BaseCurrencyID,
			    ds.CurrencyName AS BaseCurrency,
				t.ProductID, 
				CASE WHEN t.ProductID = 0 THEN 'Sportsbook' ELSE prd.ProductName END ProductName, 
				ds.Diff_amt Different,
				t.Remark
		FROM t
		INNER JOIN #diff_summary ds ON t.ProductID = ds.ProductID AND t.PartyID = ds.PartyID
		INNER JOIN OAS_Party op WITH(NOLOCK) ON t.PartyID = op.PartyID
		INNER JOIN TotalDiffAmt_Filter tf ON t.PartyID = tf.PartyID
		LEFT JOIN Product3rd prd WITH(NOLOCK) ON prd.Productid = t.ProductID
		
		ORDER BY t.PartyID, t.ProductID


	END
	DROP TABLE #tmpData_rptLicWinloss2
	DROP TABLE #LA_Data
	DROP TABLE #NAP_Data
	DROP TABLE #tmpData
	DROP TABLE #diff_summary


END

GO