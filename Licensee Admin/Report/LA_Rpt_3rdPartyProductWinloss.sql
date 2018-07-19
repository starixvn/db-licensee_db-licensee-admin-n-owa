/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_3rdPartyProductWinloss]
	  @PartyIds				VARCHAR(4000)
	, @FromDate				DATETIME
	, @ToDate				DATETIME
	, @ProductCode			VARCHAR(50)
	, @CurrencyId			INT				= 0
	, @BaseCurrencyName		VARCHAR(10)		= 'GBP'
	, @DrawFilter			SMALLINT		= 1
	, @ExcludeTest			BIT				= 0
WITH RECOMPILE
AS
/*  Created: 20150525@Florent
	Task : Report - Third Party Product Winloss
	DB: DB052.bodb02
	Revisions:
		- 20150714@Florent: support credit licensee
		- 20150722@Florent: fix bug NoDraw filter
		- 20161022@Jim:move table to bodb_licenseereport [RedmineID :#60449]
		- 20171219@Bruce: increase length for variables [#88197]
		- 20180716@bruce: add new group TEST for credit [#98126]
		
	Param's Explanation:
		+ @ProductCode:	+ 'GD'	Gold Deluxe
*/
SET NOCOUNT ON
BEGIN
	CREATE TABLE #Result (
			PartyID			INT
			, ParentId		INT
			, Winlostdate	DATETIME
			, CurrencyId	INT
			, TurnOver		MONEY
			, Winlost		MONEY
			, LicenseeWL	MONEY
			, Company		MONEY
			, Amtdueto		MONEY
			, Betcount		BIGINT)
	DECLARE @tmpParty AS TABLE (
		PartyId				INT
		, ParentId			INT
		, LicenseeId		INT
		, IsDeposit			INT
		, ProductID			INT
		, Rate				MONEY
		, Rate3rd			MONEY
		, FromDate			SMALLDATETIME
		, ToDate			SMALLDATETIME)
	CREATE TABLE #Bettype (Bettype INT, ProductId INT)
	CREATE TABLE #Exchange( ExchangeDate DATE, ExchangeID INT, CurrencyCode VARCHAR(10), Rate FLOAT)
	CREATE TABLE #PartyList(PartyId INT, PartyName VARCHAR(100), BrandName VARCHAR(100), ParentId INT)

	INSERT INTO #PartyList
	EXEC bodb_licensee.dbo.LA_PartyListSel

	INSERT INTO @tmpParty(PartyId, ParentId, LicenseeId, IsDeposit, ProductID, Rate, Rate3rd, Fromdate, Todate)
	(
		SELECT a.PartyID, p.ParentId, LicenseeID, a.isDeposit, a.ProductID, DI_Rate, CASE WHEN a.isDeposit = 0 THEN a.DI_Rate ELSE b.Rate END AS Rate3rd, a.Fromdate, a.Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCode, 'OA', @ExcludeTest) a
			LEFT JOIN #PartyList p ON a.PartyID = p.PartyId
			LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo b WITH (NOLOCK) ON p.ParentId = b.FromParty AND a.ProductID = b.ProductID AND (a.Fromdate BETWEEN b.FromDate AND b.ToDate OR a.Todate BETWEEN b.FromDate AND b.ToDate )
	)
	INSERT INTO #Bettype (Bettype, ProductID)
	(
		SELECT Bettype, ProductID
		FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0, 'GD')
	)
	DECLARE @Recommend VARCHAR(MAX) = '', @SQL VARCHAR(8000) = ''
	CREATE TABLE #DataWinloss3rd (Recommend	INT, Winlostdate DATETIME, SportType INT, Currency INT, TurnOver MONEY, TotalTrans INT, Winloss MONEY)
	DECLARE @TempAG AS TABLE( LicenseeeID INT, CustId INT, CurrencyId INT)

	-- Product <> BA
	IF (CHARINDEX('GD', @ProductCode) <> 0)-- GD
	BEGIN
		--get licensee recommend
		INSERT INTO @TempAG(LicenseeeID, CustId, CurrencyId)
		SELECT DISTINCT LicenseeID, CustID, Currency
		FROM bodb_licensee.dbo.f_SelLicenseeCust(0)
		WHERE (@CurrencyId = 0 OR (@CurrencyId <> 0 AND Currency = @CurrencyId))
			AND (@ExcludeTest = 0 OR (@ExcludeTest <> 0 AND Currency <> 20))
			AND LicenseeID IN (SELECT DISTINCT LicenseeId FROM @tmpParty WHERE IsDeposit = 1)

		SELECT @Recommend = @Recommend + CAST(CustID AS VARCHAR) + ','
		FROM @TempAG

		--truncate last comma
		SET @Recommend = SUBSTRING(@Recommend, 0, LEN(@Recommend))

		IF LEN(@Recommend) > 8000
			SET @Recommend = ''

		INSERT INTO #DataWinloss3rd(Recommend, Winlostdate, Currency, TurnOver, TotalTrans, Winloss)
		EXECUTE dbo.LA_Rpt_ThirdPartyProductWinloss
				@ProductCodes	= @ProductCode
				, @Recommend	= @Recommend
				, @Currency 	= @CurrencyId
				, @DrawFilter	= @DrawFilter
				, @FromDate 	= @FromDate
				, @ToDate 		= @ToDate
		INSERT INTO #Result(PartyID, ParentId, Winlostdate, CurrencyId, Turnover, Winlost, LicenseeWL, Company, Amtdueto, Betcount)
		(
			SELECT
				p.PartyId
				, p.ParentId
				, b.Winlostdate
				, CurrencyID
				, SUM(Turnover) AS Turnover
				, SUM(WinLoss) AS Winlost
				, - SUM(Winloss) AS LicenseeWL
				, - SUM(WinLoss * p.Rate) AS Company
				, - SUM(WinLoss * p.Rate3rd) AS Amtdueto
				, SUM(b.TotalTrans) AS BetCount
			FROM #DataWinloss3rd b WITH (NOLOCK)
				INNER JOIN @TempAG ag ON b.Recommend = ag.CustId AND b.Currency = ag.CurrencyId
				INNER JOIN @tmpParty p ON ag.LicenseeeID = p.LicenseeId
			WHERE b.Winlostdate BETWEEN p.Fromdate AND p.Todate
				AND p.IsDeposit = 1
			GROUP BY b.Winlostdate, CurrencyID , p.PartyId, p.ParentId
			UNION ALL
			SELECT
				p.PartyId
				, p.ParentId
				, b.rptDate
				, b.CurrencyID
				, SUM(b.Turnover *
						CASE WHEN @DrawFilter IN (2, 3)
								THEN CASE WHEN b.STATUS = 111 THEN 0
										  WHEN b.STATUS IN (114, 115) AND b.Bettype != 33
											THEN 0.5 ELSE 1
								END	ELSE 1
						END) AS Turnover
				, SUM(b.WinLoss) AS Winlost
				, - SUM(b.WinLoss) AS LicenseeWL
				, - SUM(WinLoss * p.Rate) AS Company
				, - SUM(WinLoss * p.Rate3rd) AS Amtdueto
				, SUM(b.BetCount * CASE WHEN @DrawFilter = 2 AND b.STATUS = 111 THEN 0 ELSE 1 END) AS BetCount
			FROM bodb_licenseereport.dbo.rpt_Betting b WITH (NOLOCK)
				INNER JOIN @tmpParty p ON b.SiteID = p.LicenseeId
				INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype AND p.ProductID = bt.ProductId
			WHERE b.rptDate BETWEEN p.Fromdate AND p.Todate
				AND b.Status NOT IN (- 1, 103)
				AND b.customercategory NOT IN (27,28)
				AND (@CurrencyId = 0 OR (@CurrencyId <> 0 AND b.CurrencyID = @CurrencyId))
				AND (@ExcludeTest = 0 OR (@ExcludeTest <> 0 AND b.CurrencyID <> 20))
			GROUP BY b.rptDate, CurrencyID , p.PartyId, p.ParentId
		)
	END
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	SELECT
		d.ParentId					AS ParentId
		, CASE WHEN d.ParentId = 999 THEN 'Credit'
			ELSE pp.PartyName END	AS ParentName
		, d.PartyID					AS PartyID
		, CASE p.PartyName
			WHEN '18bb' THEN 'PIH'
			WHEN 'IBC'	THEN 'FDL'
			ELSE p.PartyName
			END						AS PartyName
		, SUM(Betcount)				AS Betcount
		--orginal
		, SUM(TurnOver)				AS Turnover
		, SUM(Winlost)				AS MemberWinLoss
		, SUM(LicenseeWL)			AS LicenseeWL
		, CASE WHEN SUM(d.Company) < 0 THEN 0
			ELSE SUM(d.Company)
			END 					AS Company
		, SUM(Amtdueto)				AS Amtdueto

		--Base on currency
		, SUM(TurnOver * e.Rate)	AS TurnoverBase
		, SUM(Winlost * e.Rate)		AS MemberWinLossBase
		, SUM(LicenseeWL * e.Rate)	AS LicenseeWLBase
		, CASE WHEN SUM(d.Company * e.Rate) < 0 THEN 0
			ELSE SUM(d.Company * e.Rate)
			END					AS CompanyBase
		, SUM(Amtdueto * e.Rate)	AS AmtduetoBase
	FROM
		#Result d
		INNER JOIN #Exchange e ON d.Winlostdate = e.ExchangeDate AND d.CurrencyId = e.ExchangeId
		LEFT JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON d.PartyID = p.PartyID
		LEFT JOIN bodb_licensee.dbo.OAS_Party pp WITH (NOLOCK) ON d.ParentId = pp.PartyID
	GROUP BY d.ParentId
		, pp.PartyName
		, d.PartyID
		, p.PartyName
	ORDER BY pp.PartyName ASC

	DROP TABLE #Exchange
	DROP TABLE #Result
	DROP TABLE #DataWinloss3rd
	DROP TABLE #PartyList
	DROP TABLE #Bettype
END
GO

GRANT EXECUTE ON [dbo].[LA_Rpt_3rdPartyProductWinloss] TO [bodbAdminNet] AS [dbo]
GO

GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_3rdPartyProductWinloss] TO [vnteam] AS [dbo]
GO
