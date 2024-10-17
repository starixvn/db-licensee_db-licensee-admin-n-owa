/*<info serverAlias="DBLIC-bodb_Licensee" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_Rpt_VendorPaymentDetail_template14]
	@PartyIds			VARCHAR(MAX)
	,@ProductID			INT
	,@FromDate			DATETIME
	,@ToDate			DATETIME
	,@BaseCurrencyName	VARCHAR(20)
	,@TimeZoneId		INT
	,@PlatformId		TINYINT = 0
AS
/*
 * Created by : [20220405@Danny]
 * Task  : Vendor Payment Detail (template14 - PPL)
 * Revisions
	- 20210620@Danny: Initialize SP [#168387]
	- 20221003@Malcolm: Add platform filter [RedmineID: #165707]
	- 20220227@Danny: Incorporate USDTJP currency [RedmineID: #183461]
	- 20240924@Danny: exclude BTS currency [RedmineID: #210422]
	- 20241016@Danny: Extend parameter data length [RemineID: #212252]
 */

BEGIN
	DECLARE @ProductCode VARCHAR(50)
	DECLARE @BettypeIdList TABLE (BetTypeId INT)
	DECLARE @3rdRate TABLE(PartyID INT, ProductID INT, DI_Rate MONEY, IsDeposit INT, Fromdate SMALLDATETIME, Todate SMALLDATETIME, MinAmount MONEY DEFAULT 0, MaxAmount MONEY DEFAULT 0, CurrencyId INT)
	
	CREATE TABLE #PartyList (PartyId INT,PartyName VARCHAR(100),BrandName VARCHAR(100),ParentId INT, IsKeepNegativeAmount BIT DEFAULT 0)
	
	CREATE TABLE #ChargeRate (
		ChargeID		INT
		,PartyID		INT
		,LicenseeID		INT
		,isDeposit		INT
		,ProductID		INT
		,Rate			MONEY	DEFAULT 0
		,Rate3rd		MONEY	DEFAULT 0
		,Fromdate		SMALLDATETIME
		,Todate			SMALLDATETIME
	)

	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(65),
		Rate			FLOAT
	)

	CREATE TABLE #TempData (
		PartyID			INT,
		PartyName		NVARCHAR(100),
		ParentId		INT,
		ParentName		NVARCHAR(100),
		Winlostdate		DATETIME,
		CurrencyId		INT,
		Turnover		MONEY	DEFAULT 0,
		TotalTrans		INT		DEFAULT 0,
		CustomerWinLoss MONEY	DEFAULT 0,
		LicenseeWinloss MONEY	DEFAULT 0,
		LicensingFee	MONEY	DEFAULT 0,
		PayToSupplier	MONEY	DEFAULT 0,
		isDeposit		BIT,
		-- AGC
		ApplyValue		MONEY	DEFAULT 0
	)

	IF ISNULL(@PlatformId, 0) <> 0
	BEGIN
		SELECT @PartyIds = ISNULL(STRING_AGG(CONVERT(VARCHAR(50), p.PartyID), ','), '')
		FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
			INNER JOIN bodb_licensee.dbo.Licensees la WITH(NOLOCK) ON p.OldRefID = la.LicenseeID
		    INNER JOIN DBOIC.bodb_OIC.dbo.Licensee l WITH(NOLOCK) ON l.RegisteredLicenseeName = la.LicenseeName AND l.PlatformId = @PlatformId
		WHERE p.PartyID IN (SELECT value FROM STRING_SPLIT(@PartyIds, ',')) 
	END

	 -- Exchange
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, CASE WHEN ExchangeID = 51 THEN 'INH' 
										  WHEN ExchangeID = 92 THEN 'HID'  
										  ELSE Code END, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	
	-- ProductCode
	SELECT @ProductCode = ProductPrefix FROM dbo.Product3rd WITH(NOLOCK) WHERE Productid = @ProductID

	-- Party list
	INSERT INTO #PartyList (PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel

	UPDATE #PartyList SET PartyName = REPLACE(PartyName,' Licensees','') WHERE ParentId = 0
	
	UPDATE t 
	SET t.IsKeepNegativeAmount = CASE WHEN u.PartyId IS NULL THEN 0 ELSE 1 END 
	FROM #PartyList t 
	LEFT JOIN bodb_Licensee.dbo.LA_f_JVPartyListSel() u ON u.PartyId = t.PartyId

	-- Bettype List
	INSERT INTO @BettypeIdList (BetTypeId)
	SELECT	DISTINCT bettype
	FROM	bodb_licensee.dbo.LA_f_BettypeProductMapping(0,@ProductCode) la

	INSERT INTO @3rdRate (PartyId, FromDate, ToDate, CurrencyId, MinAmount, MaxAmount, DI_Rate)
	SELECT DISTINCT p.PartyId, r.FromDate, r.ToDate, c.BaseCurrencyId, c.MinAmount - CASE WHEN c.MinAmount = 0 THEN 0 ELSE 1 END, c.MaxAmount, c.Rate
	FROM dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, @ProductCode, 'OA') r
		INNER JOIN #PartyList p ON p.ParentId = r.PartyId
		INNER JOIN dbo.OAS_ChargeInfo c WITH (NOLOCK) ON r.ChargeId = c.ChargeId

	INSERT INTO #ChargeRate (ChargeId, PartyId, LicenseeId, IsDeposit, Rate, FromDate, ToDate)
	SELECT DISTINCT c.ChargeId, c.PartyId, c.LicenseeId, c.IsDeposit, c.DI_Rate, c.FromDate, c.ToDate
	FROM dbo.LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate, @ToDate, @ProductCode) c
	WHERE (c.IsDeposit = 0 AND c.DI_Rate = 0) OR (c.IsDeposit = 1 AND c.DI_Rate > 0)

	-- Region: TempData 
	IF @TimeZoneId = 1 --GMT -4
	BEGIN
		INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,Turnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee,PayToSupplier,isDeposit)
		SELECT ci.PartyId,
			b.rptDate		  AS Winlostdate,
			b.CurrencyId,
			SUM(b.Turnover)   AS Turnover,
			SUM(b.BetCount)	  AS TotalTrans,
			SUM(b.MemberWL)	  AS CustomerWinLoss,
			SUM(-b.MemberWL)  AS LicenseeWinloss,
			SUM(-b.MemberWL * ISNULL(cr.Rate, ci.Rate)) AS LicensingFee,
			SUM(-b.MemberWL * ISNULL(ci.Rate3rd, 0))	AS PayToSupplier,
			ci.isDeposit
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate
			LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.ChargeID AND cr.CurrencyID = b.CurrencyId
		WHERE b.rptDate BETWEEN @FromDate AND @ToDate 
			AND b.StatusId NOT IN (-1, 101, 102, 103) 
			AND b.CurrencyId NOT IN ( SELECT x.ExchangeID FROM LA_f_ExcludedCurrencyListSel() x)
			AND b.CustomerCategory NOT IN (27,28)
			AND b.ProductID = @ProductID
		GROUP BY b.rptDate, ci.PartyId, b.CurrencyId, ci.isDeposit
	END
	ELSE
	BEGIN
		INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,Turnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee,PayToSupplier,isDeposit)
		SELECT ci.PartyId,
			b.rptDate3rd		  AS Winlostdate,
			b.CurrencyId,
			SUM(b.Turnover)   AS Turnover,
			SUM(b.BetCount)	  AS TotalTrans,
			SUM(b.Winloss)	  AS CustomerWinLoss,
			SUM(-b.Winloss)  AS LicenseeWinloss,
			SUM(-b.Winloss * ISNULL(cr.Rate, ci.Rate)) AS LicensingFee,
			SUM(-b.Winloss * ISNULL(ci.Rate3rd, 0))	AS PayToSupplier,
			ci.isDeposit
		FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
			INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.rptDate3rd BETWEEN ci.FromDate AND ci.ToDate
			LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.ChargeID AND cr.CurrencyID = b.CurrencyId
		WHERE b.RptDate BETWEEN DATEADD(DAY, -1, @FromDate) AND DATEADD(DAY, 1, @ToDate)
			AND b.rptDate3rd BETWEEN @FromDate AND @ToDate 
			AND b.StatusId NOT IN (-1, 101, 102, 103) 
			AND b.CurrencyId NOT IN ( SELECT x.ExchangeID FROM LA_f_ExcludedCurrencyListSel() x)
			AND b.BetTypeId IN (SELECT x.BetTypeId FROM @BettypeIdList x)
		GROUP BY b.rptDate3rd, ci.PartyId, b.CurrencyId, ci.isDeposit
	END

	-- Region: Calculate result
	CREATE TABLE #Result (
		PartyId			INT,
		PartyName		VARCHAR(100),
		ParentId		INT,
		ParentName		VARCHAR(100),
		WinLossDate		DATETIME,
		CurrencyId		INT,
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		IsKeepNegativeAmount BIT
	)
	
	INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyId, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier, IsKeepNegativeAmount)
	SELECT td.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.Winlostdate, td.CurrencyId, td.TotalTrans, td.Turnover, td.CustomerWinLoss, td.LicenseeWinloss, td.LicensingFee, td.PayToSupplier, p.IsKeepNegativeAmount
	FROM #TempData td
		INNER JOIN #PartyList p ON td.PartyId = p.PartyID
		INNER JOIN #PartyList pa ON p.ParentId = pa.PartyId	

	DECLARE @Total TABLE (
		PartyId			INT,
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY,
		Currency		VARCHAR(20)
	)

	-- Region: Calculate Grand Total
	DECLARE @tempCurrency VARCHAR(20)
	DECLARE @BaseCurrencies TABLE(
		Id INT,
		Name VARCHAR(20)
	)
	INSERT INTO @BaseCurrencies(Id, Name)
	EXEC bodb_licensee.dbo.LA_SelBaseCurrency

	DECLARE @GrandTotal TABLE (
		CurrencyName	VARCHAR(20),
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY
	)
	DECLARE @BaseCurrencyRate TABLE (ExchangeId INT, ExchangeDate DATETIME, BaseCurrencyName VARCHAR(20), Rate FLOAT)
		INSERT INTO @BaseCurrencyRate (ExchangeId, ExchangeDate, BaseCurrencyName, Rate)
		SELECT e.ExchangeId, e.ExchangeDate, bc.Name, e.BaseCurrencyRate
		FROM @BaseCurrencies bc
			CROSS APPLY bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, bc.Name) e

		;WITH CTE_SumByParty AS (
			SELECT CASE WHEN  r.PartyId = 14 THEN 14 ELSE r.ParentId END ParentId, e.BaseCurrencyName,
				SUM(r.TotalTrans)				AS TotalTrans,
				SUM(r.Turnover * e.Rate)		AS Turnover,
				SUM(r.CustomerWinLoss * e.Rate) AS CustomerWinLoss,
				SUM(r.LicenseeWinLoss * e.Rate) AS LicenseeWinLoss,
				SUM(r.LicensingFee * e.Rate)	AS LicensingFee, r.IsKeepNegativeAmount
			FROM #Result r
				INNER JOIN @BaseCurrencyRate e ON e.ExchangeId = r.CurrencyId AND e.ExchangeDate = r.WinLossDate
			GROUP BY CASE WHEN  r.PartyId = 14 THEN 14 ELSE r.ParentId END, r.PartyId, e.BaseCurrencyName, r.IsKeepNegativeAmount
		)
		INSERT INTO @Total (Currency, PartyId, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee)
		SELECT BaseCurrencyName, ParentId,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(CustomerWinLoss),
			SUM(LicenseeWinLoss),
			SUM(CASE WHEN LicensingFee < 0 AND IsKeepNegativeAmount = 0 THEN 0 ELSE LicensingFee END)
		FROM CTE_SumByParty
		GROUP BY BaseCurrencyName, ParentId

		-- Total by Party
		DECLARE @TotalByParty TABLE
		(
			PartyId			INT,
			PartyName		VARCHAR(100),
			ParentId		INT,
			TotalTrans		INT,
			Turnover		MONEY,
			CustomerWinLoss	MONEY,
			LicenseeWinLoss	MONEY,
			LicensingFee	MONEY,
			PayToSupplier	MONEY,
			IsKeepNegativeAmount	BIT
		)
		INSERT INTO @TotalByParty (PartyId, PartyName, ParentId, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, IsKeepNegativeAmount)
		SELECT r.PartyId, r.PartyName, r.ParentId,
			SUM(r.TotalTrans),
			SUM(r.Turnover * e.Rate),
			SUM(r.CustomerWinLoss * e.Rate),
			SUM(r.LicenseeWinLoss * e.Rate),
			CASE WHEN SUM(r.LicensingFee * e.Rate) > 0 THEN SUM(r.LicensingFee * e.Rate) ELSE 0 END,
			r.IsKeepNegativeAmount
		FROM #Result r
			INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeId AND r.WinLossDate = e.ExchangeDate
		GROUP BY r.PartyId, r.PartyName, r.ParentId, r.IsKeepNegativeAmount

		-- Update PayToSupplier base on Licensee WL
		DECLARE @CurrencyId INT, @CurrencyName VARCHAR(100)
		SELECT TOP 1 @CurrencyId = CurrencyId FROM @3rdRate WHERE CurrencyId IS NOT NULL

		IF @CurrencyId IS NULL
			SELECT @CurrencyId = ID FROM @BaseCurrencies WHERE Name = @BaseCurrencyName
	
		SELECT @CurrencyName = Code FROM bodb02.dbo.Exchange WITH (NOLOCK) WHERE ExchangeId = @CurrencyId

		UPDATE @3rdRate SET CurrencyId = @CurrencyId WHERE CurrencyId IS NULL
		UPDATE @3rdRate SET MinAmount = 0, MaxAmount = 10000000000000 WHERE MinAmount IS NULL OR MaxAmount IS NULL

		-- Detail
		;WITH CTE_Sum AS (
			SELECT t.PartyId, t.CurrencyId, t.WinLossDate, e.BaseCurrencyRate, SUM(t.LicenseeWinloss * e.BaseCurrencyRate) AS LicenseeWinloss
			FROM bodb02.dbo.LA_f_ExchangeDailySel (@FromDate, @ToDate, @CurrencyName) e
				INNER JOIN #Result t ON t.CurrencyId = e.ExchangeId AND e.ExchangeDate = t.WinLossDate
			GROUP BY t.PartyId, t.CurrencyId, t.WinLossDate, e.BaseCurrencyRate
		), CTE_3rdRate AS (
			SELECT s.PartyId, s.CurrencyId, s.WinLossDate, SUM(CASE WHEN s.BaseCurrencyRate = 0 THEN 0 ELSE (CASE WHEN s.LicenseeWinloss <= r.MaxAmount THEN s.LicenseeWinloss ELSE r.MaxAmount END - r.MinAmount) * r.DI_Rate / s.BaseCurrencyRate END) AS PayToSupplier
			FROM CTE_Sum s
				INNER JOIN @3rdRate r ON s.PartyId = r.PartyId AND (s.LicenseeWinloss > r.MinAmount OR (s.LicenseeWinloss < 0 AND r.MinAmount = 0))
			GROUP BY s.PartyId, s.CurrencyId, s.WinLossDate
		)
		UPDATE t
		SET t.PayToSupplier = ISNULL(r.PayToSupplier, 0)
		FROM #Result t
			LEFT JOIN CTE_3rdRate r ON t.PartyId = r.PartyId AND t.CurrencyId = r.CurrencyId AND t.WinLossDate = r.WinLossDate

		-- TotalByParty
		;WITH CTE_Sum AS (
			SELECT r.PartyId, SUM(r.LicenseeWinloss * e.Rate) AS LicenseeWinloss
			FROM #Result r
				INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeId AND r.WinLossDate = e.ExchangeDate
			GROUP BY r.PartyId
		), CTE_3rdRate AS (
			SELECT r.PartyId, r.MinAmount * e.Rate AS MinAmount, r.MaxAmount * e.Rate AS MaxAmount, r.DI_Rate
			FROM @3rdRate r
				INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeId AND e.ExchangeDate = @ToDate
		), CTE_Final AS (
			SELECT s.PartyId, SUM((CASE WHEN s.LicenseeWinloss <= r.MaxAmount THEN s.LicenseeWinloss ELSE r.MaxAmount END - r.MinAmount) * r.DI_Rate) AS PayToSupplier
			FROM CTE_Sum s
				INNER JOIN CTE_3rdRate r ON s.PartyId = r.PartyId AND (s.LicenseeWinloss > r.MinAmount OR (s.LicenseeWinloss < 0 AND r.MinAmount = 0))
			GROUP BY s.PartyId
		)
		UPDATE t
		SET t.PayToSupplier = ISNULL(f.PayToSupplier, 0)
		FROM @TotalByParty t
			LEFT JOIN CTE_Final f ON t.PartyId = f.PartyId

		-- Total
		;WITH CTE_Sum AS (
			SELECT CASE WHEN r.PartyId = 14 THEN 14 ELSE r.ParentId END ParentId, br.BaseCurrencyName, SUM(r.LicenseeWinloss * br.Rate) AS LicenseeWinloss
			FROM #Result r
				INNER JOIN @BaseCurrencyRate br ON r.CurrencyId = br.ExchangeId AND r.WinLossDate = br.ExchangeDate
			GROUP BY CASE WHEN r.PartyId = 14 THEN 14 ELSE r.ParentId END, br.BaseCurrencyName
		), CTE_3rdRate AS (
			SELECT DISTINCT p.ParentId, br.BaseCurrencyName, r.MinAmount * br.Rate AS MinAmount, r.MaxAmount * br.Rate AS MaxAmount, r.DI_Rate
			FROM @3rdRate r
				INNER JOIN #PartyList p ON p.PartyId = r.PartyId
				INNER JOIN @BaseCurrencyRate br ON r.CurrencyId = br.ExchangeId AND br.ExchangeDate = @ToDate
		), CTE_Final AS (
			SELECT s.ParentId, s.BaseCurrencyName, SUM(CASE WHEN 
														(CASE WHEN s.LicenseeWinloss <= r.MaxAmount THEN s.LicenseeWinloss ELSE r.MaxAmount END - r.MinAmount) * r.DI_Rate < 0 THEN 0
														ELSE (CASE WHEN s.LicenseeWinloss <= r.MaxAmount THEN s.LicenseeWinloss ELSE r.MaxAmount END - r.MinAmount) * r.DI_Rate END
													  ) AS PayToSupplier
			FROM CTE_Sum s
				INNER JOIN CTE_3rdRate r ON s.ParentId = r.ParentId AND s.BaseCurrencyName = r.BaseCurrencyName AND (s.LicenseeWinloss > r.MinAmount OR (s.LicenseeWinloss < 0 AND r.MinAmount = 0))
			GROUP BY s.ParentId, s.BaseCurrencyName
		)
		UPDATE t
		SET t.PayToSupplier = ISNULL(f.PayToSupplier, 0)
		FROM @Total t
			LEFT JOIN CTE_Final f ON t.PartyId = f.ParentId AND t.Currency = f.BaseCurrencyName

		-- Return data
		BEGIN
			-- Detail by Parties
			SELECT 
				r.PartyId,
				r.PartyName,
				CASE WHEN r.PartyId = 14 THEN 14 ELSE r.ParentId END ParentId,
				CASE WHEN r.PartyId = 14 THEN '12Bet' ELSE r.ParentName END ParentName,
				r.WinLossDate,
				e.CurrencyCode AS CurrencyName,
				r.TotalTrans,
				-- Original Currency
				r.Turnover			AS TurnoverOriginal,
				r.CustomerWinLoss	AS CustomerWinLossOriginal,
				r.LicenseeWinLoss	AS LicenseeWinLossOriginal,
				r.LicensingFee		AS LicensingFeeOriginal,
				r.PayToSupplier		AS PayToSupplierOriginal,
				r.LicensingFee - r.PayToSupplier AS CompanyIncomeOriginal,
				-- Base Currency
				CONVERT(MONEY, r.Turnover * e.Rate)			AS Turnover,
				CONVERT(MONEY, r.CustomerWinLoss * e.Rate)	AS CustomerWinLoss,
				CONVERT(MONEY, r.LicenseeWinLoss * e.Rate)	AS LicenseeWinLoss,
				CONVERT(MONEY, r.LicensingFee * e.Rate)		AS LicensingFee,
				CONVERT(MONEY, r.PayToSupplier * e.Rate)	AS PayToSupplier,
				CONVERT(MONEY, (r.LicensingFee - r.PayToSupplier) * e.Rate) AS CompanyIncome
			FROM #Result r
				INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeId AND r.WinLossDate = e.ExchangeDate
	

			-- Total by Party
			SELECT	PartyId, 
					PartyName, 
					CASE WHEN PartyId = 14 THEN 14 ELSE ParentId END ParentId, 
					TotalTrans, 
					Turnover, 
					CustomerWinLoss, 
					LicenseeWinLoss, 
					CASE WHEN LicensingFee < 0 AND IsKeepNegativeAmount = 0  THEN 0 ELSE  LicensingFee END LicensingFee, 
					PayToSupplier  , 
					CASE WHEN LicensingFee < 0 AND IsKeepNegativeAmount = 0  THEN 0 ELSE  LicensingFee END - PayToSupplier  AS CompanyIncome
			FROM @TotalByParty

			-- Grand Total
			SELECT
				Currency				AS CurrencyName
				,SUM(TotalTrans)		AS TotalTrans
				,SUM(Turnover)			AS Turnover
				,SUM(CustomerWinLoss)	AS CustomerWinLoss
				,SUM(LicenseeWinLoss)	AS LicenseeWinLoss
				,SUM(LicensingFee)		AS LicensingFee
				,SUM(PayToSupplier)		AS PayToSupplier
				,SUM(LicensingFee - PayToSupplier) AS CompanyIncome
			FROM @Total
			GROUP BY Currency

			-- Total
			SELECT
				PartyId,
				TotalTrans,
				Turnover,
				CustomerWinLoss,
				LicenseeWinLoss,
				LicensingFee,
				PayToSupplier,
				LicensingFee - PayToSupplier AS CompanyIncome
			FROM @Total
			WHERE Currency = @BaseCurrencyName
		END


	DROP TABLE	#PartyList
	DROP TABLE	#Exchange
	DROP TABLE	#ChargeRate
	DROP TABLE  #TempData	
	DROP TABLE  #Result
	
END
GO