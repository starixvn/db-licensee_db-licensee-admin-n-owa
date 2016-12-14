USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_NumberGame2Winloss]    Script Date: 20161213 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[LA_Rpt_NumberGame2Winloss] 
	 @PartyIDs				VARCHAR(5500)
	, @FromDate				SMALLDATETIME
	, @ToDate				SMALLDATETIME	
	, @IsConvert			BIT				= 1
	, @BaseCurrencyName		VARCHAR(3)		= 'GBP'
	, @ExcludeTest			BIT				= 0
AS      
  
/*  
 * Created by : [20161214@Scofield.Huynh]  
 * Task  : Get Number Game 2 Winloss 
 * DB   : DB052.bodb_licensee   
 */  
BEGIN
	SET NOCOUNT ON	
	
	-- Get ProductId
	DECLARE @ProductId INT = (SELECT TOP 1 ProductId FROM dbo.Product3rd WITH(NOLOCK) WHERE ProductPrefix='NG2')

	-- ChargeRate
	DECLARE @ChargeRate TABLE(Rate MONEY, ChargeType TINYINT, FromDate DATETIME, ToDate DATETIME)
	INSERT INTO @ChargeRate (Rate, ChargeType, FromDate, ToDate)
	(
		SELECT Rate, ChargeType,
			CASE WHEN @FromDate <= FromDate THEN FromDate ELSE @FromDate END,
			CASE WHEN @ToDate >= ToDate THEN ToDate ELSE @ToDate END
		FROM dbo.OAS_ChargeInfo WITH(NOLOCK) 
		WHERE ProductID=@ProductId AND FromParty=1 AND (
			@FromDate BETWEEN FromDate AND ToDate OR
			@ToDate BETWEEN FromDate AND ToDate OR
			FromDate BETWEEN @FromDate AND @ToDate OR
			ToDate BETWEEN @FromDate AND @ToDate
		)
	)	

	-- Party list
	BEGIN
		DECLARE @PartyList AS TABLE (PartyId INT, LicenseeId INT, IsDeposit BIT)

		INSERT INTO @PartyList
		SELECT p.PartyID, CASE WHEN ISNULL(d.IsDeposit,0) = 1 THEN p.OldRefID ELSE l.LabelID END, ISNULL(d.IsDeposit,0)
		FROM dbo.OAS_Party p WITH(NOLOCK)
		INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON p.PartyID=d.PartyID
		LEFT JOIN dbo.Labels l WITH(NOLOCK) ON l.LicenseeID = p.OldRefID
		WHERE p.PartyID IN (SELECT val FROM dbo.strSplit(@PartyIDs, ','))
	END

	-- Party group List
	BEGIN
		DECLARE @PartyGroupList AS TABLE (
			PartyId		INT,
			PartyName	VARCHAR(100),
			BranchName	VARCHAR(100),
			ParentId	INT
		)

		INSERT INTO @PartyGroupList (PartyId, PartyName, BranchName, ParentId)
		EXEC dbo.LA_PartyListSel

		UPDATE @PartyGroupList SET PartyName=REPLACE(PartyName,' Licensees','') WHERE ParentId=0
	END
	
	-- Base currencies
	BEGIN	
		DECLARE @BaseCurrencies TABLE(
			CurrencyId	INT,
			Code		VARCHAR(10),
			IsApply		BIT
		)
		INSERT INTO @BaseCurrencies(CurrencyId, Code)
		EXEC bodb_Licensee.dbo.LA_SelBaseCurrency		
	END
	
	-- Get Data
	CREATE TABLE #TempData (
		 PartyId			INT,
		 RptDate			DATETIME,
		 CurrencyId			INT,
		 TotalTrans			INT,
		 Turnover			FLOAT,
		 CustomerWinLoss	FLOAT,
		 LicenseeWinLoss	FLOAT,
		 LicensingFee		FLOAT,
		 PayToSupplier		FLOAT,
		 CompanyIncome		FLOAT)		

	INSERT INTO #TempData (PartyId, RptDate, CurrencyId, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier, CompanyIncome)
	SELECT p.PartyId, b.rptDate, b.CurrencyId, b.BetCount, b.Turnover, b.MemberWL, -b.MemberWL, 0, (-b.MemberWL) * r.Rate, (-b.MemberWL) * r.Rate		
	FROM bodb_licenseereport.dbo.rpt_BettingByProduct b WITH (NOLOCK) 
	INNER JOIN @PartyList p ON b.SiteID = p.LicenseeId
	INNER JOIN @ChargeRate r ON b.rptDate BETWEEN r.FromDate AND r.ToDate
	WHERE b.StatusId NOT IN (-1, 101, 102, 103)
		AND b.Bettype BETWEEN 2501 AND 2699
		AND b.CustomerCategory NOT IN (27, 28)
		AND (@ExcludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyId <> 20))
		AND p.IsDeposit = 0

	-- Calculate result
	CREATE TABLE #TempResult (
		 PartyId					INT,
		 PartyName					VARCHAR(100),
		 GroupName					VARCHAR(100),
		 RptDate					DATETIME,
		 CurrencyId					INT,
		 CurrencyName				VARCHAR(10),
		 TotalTrans					INT,
		 Turnover					FLOAT,
		 CustomerWinLoss			FLOAT,
		 LicenseeWinLoss			FLOAT,
		 LicensingFee				FLOAT,
		 PayToSupplier				FLOAT,
		 CompanyIncome				FLOAT)			 
	CREATE TABLE #Result (
		 PartyId					INT,
		 PartyName					VARCHAR(100),
		 GroupName					VARCHAR(100),
		 ReportDate					DATETIME,
		 CurrencyName				VARCHAR(10),
		 TotalTrans					INT,
		 Turnover					FLOAT,
		 CustomerWinLoss			FLOAT,
		 LicenseeWinLoss			FLOAT,
		 LicensingFee				FLOAT,
		 PayToSupplier				FLOAT,
		 CompanyIncome				FLOAT)		 
	CREATE TABLE #Totals (
		 PartyId					INT,		 
		 PartyName					VARCHAR(100),
		 GroupName					VARCHAR(100),
		 TotalTrans					INT,
		 Turnover					FLOAT,
		 CustomerWinLoss			FLOAT,
		 LicenseeWinLoss			FLOAT,
		 LicensingFee				FLOAT,
		 PayToSupplier				FLOAT,
		 CompanyIncome				FLOAT)			 
	CREATE TABLE #GrandTotals (
		 CurrencyName		VARCHAR(10),
		 TotalTrans			INT,
		 Turnover			FLOAT,
		 CustomerWinLoss	FLOAT,
		 LicenseeWinLoss	FLOAT,
		 LicensingFee		FLOAT,
		 PayToSupplier		FLOAT,
		 CompanyIncome		FLOAT)			 
	CREATE TABLE #Exchange(
		ExchangeDate	DATETIME,
		ExchangeId		INT,
		Code			VARCHAR(10),
		Rate			FLOAT
	)	
	DECLARE @TempCurrency VARCHAR(10)

	WHILE EXISTS (SELECT * FROM @BaseCurrencies WHERE IsApply IS NULL)
	BEGIN
		SET @TempCurrency = (SELECT TOP 1 Code FROM @BaseCurrencies WHERE IsApply IS NULL)
		
		INSERT INTO #Exchange(ExchangeDate, ExchangeId,Code,Rate)
		SELECT exchangedate, ExchangeId,Code, BaseCurrencyRate
		FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @TempCurrency)

		INSERT INTO #TempResult(PartyId, PartyName, GroupName, RptDate, CurrencyId, CurrencyName, TotalTrans, 
			Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier, CompanyIncome)
		SELECT t.PartyId, p.PartyName, g.PartyName, t.RptDate, t.CurrencyId, e.Code, t.TotalTrans, 
			t.Turnover * e.Rate, t.CustomerWinLoss * e.Rate, t.LicenseeWinLoss * e.Rate, t.LicensingFee * e.Rate, t.PayToSupplier * e.Rate, t.CompanyIncome * e.Rate
		FROM #TempData t
		INNER JOIN #Exchange e ON e.ExchangeDate = t.RptDate AND e.ExchangeId = t.CurrencyId
		INNER JOIN @PartyGroupList p ON t.PartyId = p.PartyId AND p.ParentId > 0
		INNER JOIN @PartyGroupList g ON p.ParentId= g.PartyId AND g.ParentId = 0

		IF @TempCurrency = @BaseCurrencyName
		BEGIN
			IF @IsConvert = 1 -- Only convert data to BaseCurrencyName when IsConvert = 1
			BEGIN
				INSERT INTO #Result(PartyId, PartyName, GroupName, ReportDate, CurrencyName, TotalTrans, 
				Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier, CompanyIncome)
				SELECT PartyId, PartyName, GroupName, RptDate, CurrencyName, TotalTrans, 
					Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier, CompanyIncome
				FROM #TempResult
			END
			
			-- Always convert to BaseCurrencyName when calculate totals grouped by partyid
			INSERT INTO #Totals(PartyId, PartyName, GroupName, TotalTrans,Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier, CompanyIncome)
			SELECT PartyId, PartyName, GroupName, SUM(TotalTrans), SUM(Turnover), SUM(CustomerWinLoss), SUM(LicenseeWinLoss), SUM(LicensingFee), SUM(PayToSupplier), SUM(CompanyIncome)
			FROM #TempResult
			GROUP BY PartyId, PartyName, GroupName
		END
		
		INSERT INTO #GrandTotals (CurrencyName, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier, CompanyIncome)
		SELECT @TempCurrency, SUM(TotalTrans), SUM(Turnover), SUM(CustomerWinLoss), SUM(LicenseeWinLoss), SUM(LicensingFee), SUM(PayToSupplier), SUM(CompanyIncome)
		FROM #TempResult

		UPDATE @BaseCurrencies SET IsApply = 1 WHERE Code = @TempCurrency
		DELETE #Exchange
		DELETE #TempResult
	END
	
	-- Return Data
	IF @BaseCurrencyName <> '' AND @IsConvert = 1
		SELECT * FROM #Result
	ELSE
		BEGIN
			INSERT INTO #Exchange(ExchangeDate, ExchangeId,Code,Rate)
			SELECT exchangedate, ExchangeId,Code, BaseCurrencyRate
			FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, 'EUR')

			SELECT t.PartyId, p.PartyName, g.PartyName as GroupName, RptDate as ReportDate, e.Code as CurrencyName, TotalTrans, 
				Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier, CompanyIncome
			FROM #TempData t
			INNER JOIN #Exchange e ON e.ExchangeDate = t.RptDate AND e.ExchangeId = t.CurrencyId
			INNER JOIN @PartyGroupList p ON t.PartyId = p.PartyId AND p.ParentId > 0
			INNER JOIN @PartyGroupList g ON p.ParentId= g.PartyId AND g.ParentId = 0
		END

	SELECT * FROM #Totals
	SELECT * FROM #GrandTotals

	-- Drop temp tables
	DROP TABLE #TempResult
	DROP TABLE #Exchange
	DROP TABLE #TempData
	DROP TABLE #GrandTotals
END    

GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_NumberGame2Winloss] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_NumberGame2Winloss] TO bodbAdminNet 
