USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_GoldDeluxeWinloss] 
	  @PartyIds			VARCHAR(1000)
	, @FromDate			DATETIME
	, @ToDate			DATETIME
	, @BaseCurrencyName	VARCHAR(3) = 'EUR'
AS
/*  Created: 20161118@bruce.bui
	Task : Report - Gold Deluxe win loss
	DB: DB052.bodb_licensee
	Revisions:

	Param's Explanation:
*/
BEGIN
	SET NOCOUNT ON

	--CREATE TABLE #PartyList(
	--	PartyId		INT,
	--	PartyName	VARCHAR(100),
	--	BrandName	VARCHAR(100),
	--	ParentId	INT
	--)
	--INSERT INTO #PartyList EXEC dbo.LA_PartyListSel

	DECLARE @ChargeInfo AS TABLE (
		PartyId				INT
		, LicenseeId		INT
		, IsDeposit			INT
		, ProductId			INT
		, Rate				MONEY
		, FromDate			SMALLDATETIME
		, ToDate			SMALLDATETIME
		, IsPayToSupplier		BIT
	)

	--INSERT INTO @ChargeInfo(PartyId, LicenseeId, ProductId, Rate, IsPayToSupplier, IsDeposit, Fromdate, Todate)
	(
		SELECT PartyID, LicenseeID, ProductID, DI_Rate, 0, isDeposit, Fromdate, Todate
		FROM dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, 'GD', 'OA', 1)
		UNION ALL
		SELECT FromParty, 0, ProductID, Rate, 1,
			(CASE WHEN FromParty=1 THEN 1 ELSE 0 END) AS IsDeposit,
			(CASE WHEN FromDate < @FromDate THEN @FromDate ELSE FromDate END) AS FromDate,
			(CASE WHEN ToDate > @ToDate THEN @ToDate ELSE ToDate END) AS ToDate
		FROM dbo.OAS_ChargeInfo
		WHERE ProductId = 11 AND FromParty IN (1, 999) AND (
			FromDate BETWEEN @FromDate AND @ToDate OR
			ToDate BETWEEN @FromDate AND @ToDate OR
			@FromDate BETWEEN FromDate AND ToDate OR
			@ToDate BETWEEN FromDate AND ToDate
		)
	)

	SELECT  b.rptDate, ci.PartyID, b.currencyID
		, SUM(b.betcount) Totaltrans
		, SUM(b.turnover) Turnover
		, SUM(b.MemberWL) CustomerWL
	FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
	INNER JOIN @ChargeInfo ci ON (
									b.SiteID = ci.LicenseeID AND
									b.ProductID = ci.ProductId AND
									b.rptDate BETWEEN ci.FromDate AND ci.ToDate
								)
	WHERE b.rptDate BETWEEN @FromDate AND @ToDate AND
		  b.StatusId NOT IN (- 1, 101, 102, 103) AND
		  b.CurrencyId <> 20 AND
		  b.customercategory NOT IN (27,28)
	GROUP BY b.rptDate, ci.PartyID, b.CurrencyID


	CREATE TABLE #Exchange( ExchangeDate DATE, ExchangeID INT, CurrencyCode VARCHAR(10), Rate FLOAT)
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	(
		SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
		FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	)

	DROP TABLE #Exchange
END
GO

GRANT EXECUTE ON [dbo].[LA_Rpt_GoldDeluxeWinloss] TO [bodbAdminNet] AS [dbo]
GO

GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_GoldDeluxeWinloss] TO [vnteam] AS [dbo]
GO
