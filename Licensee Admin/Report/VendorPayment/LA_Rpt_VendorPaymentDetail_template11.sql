/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
CREATE PROCEDURE [dbo].[LA_Rpt_VendorPaymentDetail_template11]
	@PartyIds			VARCHAR(4000),
	@ProductID			INT,
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@BaseCurrencyName	VARCHAR(20),
	@TimeZoneId			INT
AS
/*
 * Created by : [20220405@Danny]
 * Task  : Vendor Payment Detail (template11 - Template for BetBuilder product, including some specific info such as: BA WL, SB WL)
 * Revisions
	- 20220426@Danny: Initialize SP [#168387]
 */

BEGIN
	SET NOCOUNT ON

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
		CurrencyCode	VARCHAR(10),
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

	)

	 -- Exchange
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT	ExchangeDate, 
			ExchangeID,  
			CASE WHEN ExchangeID = 51 THEN 'INH' 
				 WHEN ExchangeID = 92 THEN 'HID' 
				 ELSE Code END Code, 
			BaseCurrencyRate
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

	-- Handle chargeRate
	BEGIN
		IF @ProductID = 998
		BEGIN
			SELECT 1
		END
		ELSE
		BEGIN
			-- Get 3rd Rate
			INSERT INTO @3rdRate (PartyID, ProductID, DI_Rate, IsDeposit, Fromdate, Todate)
			SELECT DISTINCT p.PartyId, r.ProductID, r.DI_Rate, r.IsDeposit, r.Fromdate, r.Todate 
			FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, @ProductCode, 'OA') r 
			INNER JOIN #PartyList p on p.ParentId = r.PartyID
	
			-- ​#ChargeRate
			INSERT INTO #ChargeRate (ChargeID, PartyID, LicenseeID, isDeposit, ProductID, Rate, Rate3rd, Fromdate, Todate)
			SELECT DISTINCT c.ChargeID, c.PartyID, c.LicenseeID, c.isDeposit, c.ProductID, c.DI_Rate AS Rate, r.DI_Rate AS Rate3rd, c.Fromdate, c.Todate
			FROM bodb_licensee.dbo.LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate, @ToDate,@ProductCode) c
			INNER JOIN @3rdRate r ON r.PartyID = c.PartyID and CASE WHEN r.ProductID = 69 THEN 0 ELSE  r.ProductID END = c.ProductID
			WHERE (c.DI_Rate = 0 AND c.isDeposit = 0) OR (c.DI_Rate > 0 and c.isDeposit = 1)
		END
	END
	

	SELECT 'debug_chargeRate',* FROM #ChargeRate
	
	-- Region: TempData 
	IF @TimeZoneId = 1 --GMT -4
	BEGIN
		IF @ProductID = 22
		BEGIN
			INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,Turnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee, PayToSupplier, isDeposit)
			SELECT	ci.PartyId,
					b.rptDate,
					b.CurrencyId,
					SUM(b.Turnover) AS Turnover,
					SUM(b.BetCount) AS TotalTrans,
					SUM(b.WinLoss) AS CustomerWinLoss,
					- SUM(b.WinLoss) AS LicenseeWinloss,
					SUM(-b.WinLoss * ISNULL(cr.Rate, ci.Rate)) AS LicensingFee,
					SUM(-b.WinLoss * 
					CASE 
						WHEN ci.IsDeposit = 1 THEN (CASE WHEN bp.Bettype IS NOT NULL THEN 0.045 ELSE 0.035 END)
						ELSE (CASE WHEN bp.Bettype IS NOT NULL THEN 0.03 ELSE 0.02 END)
					END) AS PayToSupplier,
					ci.isDeposit
			FROM bodb_LicenseeReport.dbo.rpt_Betting b WITH (NOLOCK)
				INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate
				LEFT JOIN bodb02.dbo.SportBettypeMatrix  bp WITH(NOLOCK) ON b.Bettype = bp.Bettype AND bp.ProductID = @ProductID AND bp.SubProduct = 'Blueprint'
				LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON ci.ChargeId = cr.ChargeID AND cr.CurrencyID = b.CurrencyId
			WHERE b.rptDate BETWEEN @FromDate AND @ToDate AND
				b.Status NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20 AND b.CustomerCategory NOT IN (27,28)
				AND b.Bettype in (Select Bettype FROM LA_f_BettypeProductMapping(0,@ProductCode))
			GROUP BY b.rptDate, ci.PartyId, b.CurrencyId, ci.isDeposit
		END
		ELSE IF @ProductID = 23
		BEGIN 
			 ;WITH CalculateLicenseeWinLoss AS (
				SELECT r.PartyId,
					b.rptDate,
					b.CurrencyId,
					b.BetCount,
					b.Turnover,
					b.WinLoss,
					-(b.WinLoss + b.WinLossS + b.WinLossM + b.WinLossA + b.CommissionS) LicenseeWl,
					r.Rate3rd
				FROM bodb_licenseereport.dbo.rpt_Betting b WITH (NOLOCK) 
				INNER JOIN #ChargeRate r ON b.SiteID = r.LicenseeId AND b.rptDate BETWEEN r.FromDate AND r.ToDate
				WHERE b.Status NOT IN (-1, 101, 102, 103)
					AND b.Bettype in (Select Bettype FROM LA_f_BettypeProductMapping(0,@ProductCode))
					AND b.CustomerCategory NOT IN (27, 28)
					AND b.CurrencyId <> 20
					AND b.rptDate BETWEEN @FromDate AND @ToDate
			)
			INSERT INTO #TempData (PartyId, Winlostdate, CurrencyId, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier)
			SELECT PartyId,rptDate, CurrencyID, BetCount, Turnover, WinLoss, LicenseeWl , 0, LicenseeWl * Rate3rd
			FROM CalculateLicenseeWinLoss
		END
		ELSE
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
				AND b.CurrencyId <> 20 
				AND b.CustomerCategory NOT IN (27,28)
				AND b.ProductID = @ProductID
			GROUP BY b.rptDate, ci.PartyId, b.CurrencyId, ci.isDeposit
		END
	END
	ELSE -- Another timezone
	BEGIN
		IF @ProductID = 22
		BEGIN
			INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,Turnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee, PayToSupplier, isDeposit)
			SELECT	ci.PartyId,
					b.rptDate3rd,
					b.CurrencyId,
					SUM(b.Turnover) AS Turnover,
					SUM(b.BetCount) AS TotalTrans,
					SUM(b.WinLoss) AS CustomerWinLoss,
					- SUM(b.WinLoss) AS LicenseeWinloss,
					SUM(-b.WinLoss * ISNULL(cr.Rate, ci.Rate)) AS LicensingFee,
					SUM(-b.WinLoss * 
					CASE 
						WHEN ci.IsDeposit = 1 THEN (CASE WHEN bp.Bettype IS NOT NULL THEN 0.045 ELSE 0.035 END)
						ELSE (CASE WHEN bp.Bettype IS NOT NULL THEN 0.03 ELSE 0.02 END)
					END) AS PayToSupplier,
					ci.isDeposit
			FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
				INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.rptDate3rd BETWEEN ci.FromDate AND ci.ToDate
				LEFT JOIN bodb02.dbo.SportBettypeMatrix  bp WITH(NOLOCK) ON b.BettypeID = bp.Bettype AND bp.ProductID = @ProductID AND bp.SubProduct = 'Blueprint'
				LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON ci.ChargeId = cr.ChargeID AND cr.CurrencyID = b.CurrencyId
			WHERE b.RptDate BETWEEN DATEADD(DAY, -1, @FromDate) AND DATEADD(DAY, 1, @ToDate)
					AND b.rptDate3rd BETWEEN @FromDate AND @ToDate 
					AND b.StatusID NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20 
					AND b.BettypeID in (Select Bettype FROM LA_f_BettypeProductMapping(0,@ProductCode))
			GROUP BY b.rptDate3rd, ci.PartyId, b.CurrencyId, ci.isDeposit
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
				AND b.CurrencyId <> 20 
				AND b.BetTypeId IN (SELECT x.BetTypeId FROM @BettypeIdList x)
			GROUP BY b.rptDate3rd, ci.PartyId, b.CurrencyId, ci.isDeposit
		END
	END

	--- Special product
	BEGIN
		IF @ProductID = 10 -- AGC
		BEGIN
			DECLARE @ApplyRange TABLE (ParentId INT, SumApplyValue MONEY, ApplyRate MONEY)

			UPDATE td SET
				PartyName	= p.PartyName,
				ParentId	= pa.PartyId,
				ParentName	= pa.PartyName,
				ApplyValue	= CASE WHEN pa.PartyId = 1 -- group Oneworks
								THEN -td.CustomerWinLoss * ec.BaseCurrencyRate
								ELSE -td.CustomerWinLoss * eu.BaseCurrencyRate
							  END
			FROM #TempData td
			INNER JOIN #PartyList p ON td.PartyId = p.PartyID AND p.ParentId > 0		-- party
			INNER JOIN #PartyList pa ON p.ParentId = pa.PartyId AND pa.ParentId = 0		-- billing group
			INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, 'CNY') ec ON td.CurrencyId = ec.ExchangeID AND ec.ExchangeDate = td.Winlostdate
			INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, 'USD') eu ON td.CurrencyId = eu.ExchangeID AND eu.ExchangeDate = td.Winlostdate

			INSERT INTO @ApplyRange (ParentId, SumApplyValue)
			SELECT ParentId, SUM(ApplyValue)
			FROM #TempData
			GROUP BY ParentId

			UPDATE @ApplyRange
			SET ApplyRate = CASE WHEN ParentId = 1 -- Oneworks
				THEN CASE WHEN SumApplyValue <= 15000000 THEN 0.08 ELSE 0.07 END
				ELSE CASE WHEN SumApplyValue <= 2500000 THEN 0.08 ELSE 0.07 END
			END

			UPDATE r
			SET r.PayToSupplier = a.ApplyRate * r.LicenseeWinLoss
			FROM #TempData r INNER JOIN @ApplyRange a ON r.ParentId = a.ParentId
		END

		IF @ProductID = 8
		BEGIN
			DECLARE	@12BetId		INT = 14,
					@CreditGroupId	INT = 999,
					@CN88PartyId	INT = (SELECT a.PartyID FROM dbo.OAS_Party a WITH(NOLOCK) WHERE a.PartyName='CN88'),
					@TianboPartyId	INT = 432,
					@BobbetPartyId	INT = 346

			UPDATE r
			SET r.PayToSupplier = r.LicenseeWinloss * (CASE 
														WHEN r.PartyId = @CN88PartyId THEN 0.015
														WHEN r.PartyId IN (@TianboPartyId, @BobbetPartyId) THEN 0.02
														WHEN @FromDate >= CAST('2020-07-01' AS DATETIME) THEN 0.036
														WHEN r.PartyId = 14 OR  r.isDeposit = 0 OR @FromDate >= CAST('2018-8-1' AS DATETIME) THEN 0.03 
														ELSE 0.05 
													END)
			FROM #TempData r 
		END

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
	
	WHILE EXISTS (SELECT TOP 1 1 FROM @BaseCurrencies)
	BEGIN
		SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies)

		;WITH TotalByParty AS(
			SELECT  CASE WHEN  td.PartyId = 14 THEN 14 ELSE td.ParentId END ParentId, 
					td.PartyId, 
					td.IsKeepNegativeAmount,
					SUM(td.TotalTrans) TotalTrans,
					SUM(td.Turnover * e.BaseCurrencyRate) Turnover,
					SUM(td.CustomerWinLoss * e.BaseCurrencyRate) CustomerWinLoss,
					SUM(td.LicenseeWinLoss * e.BaseCurrencyRate) LicenseeWinLoss,
					SUM(td.LicensingFee * e.BaseCurrencyRate) LicensingFee,
					SUM(td.PayToSupplier * e.BaseCurrencyRate) PayToSupplier
			FROM #Result td INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency) e
			ON e.ExchangeID = td.CurrencyId AND e.ExchangeDate = td.WinLossDate
			GROUP BY CASE WHEN  td.PartyId = 14 THEN 14 ELSE td.ParentId END, td.PartyId, td.IsKeepNegativeAmount
		)
		INSERT INTO @Total (Currency,PartyId,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier,CompanyIncome)
		SELECT @tempCurrency,ParentId,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(CustomerWinLoss),
			SUM(LicenseeWinLoss),
			SUM(CASE WHEN LicensingFee < 0 AND  IsKeepNegativeAmount = 0 THEN 0 ELSE LicensingFee END),
			SUM(PayToSupplier),
			SUM( CASE WHEN @ProductID = 23 THEN LicenseeWinLoss - PayToSupplier
					ELSE CASE WHEN LicensingFee < 0 AND  IsKeepNegativeAmount = 0 THEN 0 ELSE LicensingFee END - PayToSupplier END)
		FROM TotalByParty
		GROUP BY ParentId
		
		INSERT INTO @GrandTotal (CurrencyName,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee, PayToSupplier, CompanyIncome)
		SELECT Currency,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(CustomerWinLoss),
			SUM(LicenseeWinLoss),
			SUM(LicensingFee),
			SUM(PayToSupplier),
			SUM( CASE WHEN @ProductID = 23 THEN LicenseeWinLoss - PayToSupplier ELSE LicensingFee - PayToSupplier END)
		FROM @Total
		WHERE Currency = @tempCurrency
		GROUP BY Currency

		DELETE @BaseCurrencies WHERE [Name] = @tempCurrency
	END
	
	-- Select data by Parties
	SELECT 
		r.PartyId,
		r.PartyName,
		CASE WHEN r.PartyId = 14 THEN 14 ELSE r.ParentId END ParentId,
		CASE WHEN r.PartyId = 14 THEN '12Bet' ELSE r.ParentName END ParentName,
		r.WinLossDate,
		e.CurrencyCode AS CurrencyName,
		-- Select by origin currency
		r.TotalTrans,
		r.Turnover AS TurnoverOriginal,
		CAST((r.CustomerWinLoss) AS MONEY) AS CustomerWinLossOriginal,
		CAST((r.LicenseeWinLoss) AS MONEY) AS LicenseeWinLossOriginal,
		CAST((r.LicensingFee) AS MONEY) AS LicensingFeeOriginal,
		CAST((r.PayToSupplier) AS MONEY) AS PayToSupplierOriginal,
		r.LicensingFee - r.PayToSupplier AS CompanyIncomeOriginal,
		-- Select by base currency
		r.Turnover * e.Rate AS Turnover,
		CAST((r.CustomerWinLoss * e.Rate) AS MONEY) AS CustomerWinLoss,
		CAST((r.LicenseeWinLoss * e.Rate) AS MONEY) AS LicenseeWinLoss,
		CAST((r.LicensingFee * e.Rate) AS MONEY) AS LicensingFee,
		CAST((r.PayToSupplier * e.Rate)AS MONEY) AS PayToSupplier,
		CASE WHEN @ProductID =23 THEN CAST(((r.LicenseeWinLoss - r.PayToSupplier) * e.Rate)AS MONEY)
			 ELSE CAST(((r.LicensingFee - r.PayToSupplier) * e.Rate)AS MONEY) END AS CompanyIncome
	FROM #Result r INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND r.WinLossDate = e.ExchangeDate
	
	-- Select Grand Total
	SELECT 	CurrencyName,
			TotalTrans		,
			Turnover		,
			CustomerWinLoss	,
			LicenseeWinLoss	,
			LicensingFee	,
			PayToSupplier	,
			CompanyIncome	 
	FROM @GrandTotal
	
	-- Total
	SELECT 
		PartyId,
		TotalTrans,
		Turnover,
		CustomerWinLoss,
		LicenseeWinLoss,
		LicensingFee,
		PayToSupplier,
		CompanyIncome
	FROM @Total t
	WHERE Currency = @BaseCurrencyName
	-- End Region
	
	DROP TABLE	#PartyList
	DROP TABLE	#Exchange
	DROP TABLE	#ChargeRate
	DROP TABLE  #TempData	
	DROP TABLE  #Result
END
GO