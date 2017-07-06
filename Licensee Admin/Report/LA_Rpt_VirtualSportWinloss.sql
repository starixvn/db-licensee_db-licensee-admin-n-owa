USE [bodb02]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_VirtualSportWinloss]
	@PartyIDs				VARCHAR(5500)
	, @FromDate				SMALLDATETIME
	, @ToDate				SMALLDATETIME
	, @SportType			INT			= 0
	, @BetType				INT			= 0
	, @drawfilter			SMALLINT	= 1
	, @excludeTest			BIT			= 0
	, @IsConvert			BIT			= 1
	, @BaseCurrencyName		VARCHAR(3)	= 'EUR'
AS

/*
 * Created by	: [20140911@Florent]
 * Task			: Get Virtual Sports Winloss
 * DB			: DB052.bodb02
 * Base on		: [OA_Rpt_VirtualSportWinloss]
 * Revisions	:
		- 20141111@Florent: using new OAS_ChargeInfo structure and use unique formula
		- 20150326@Florent: fix filter drawfilter
		- 20150703@Florent: add GBP
		- 20160115@Victor: Show data of credit licensees regardless Charge Rate = 0 [Redmine: #50829]
		- 20161022@Jim:move table to bodb_licenseereport [RedmineID :#60449]
		- 20170620@Bruce: add paytosupplier and netincome [#78398]
 * Param's Explanation:
 *  - @FromDate   : From date
 *  - @ToDate   : To date
 *  - @Sporttype   : Sporttype
 *  - @BetList:  Bettype offered for Virtual sports (0:All Bettype)
 *  - @drawfilter:  'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
 *  - @excludeTest:
			0 - Get all currency in date range from - to
			1 - get only real currency from licensee_launch_date/from_date to to_date
 */

BEGIN

SET NOCOUNT ON

CREATE TABLE #Party (PartyId INT,PartyName VARCHAR(100),BrandName VARCHAR(100),ParentId INT)
INSERT INTO #Party EXEC bodb_licensee.dbo.LA_PartyListSel

CREATE TABLE #ChargeInfo (
	 PartyID		INT
	,LicenseeID		INT
	,isDeposit		INT
	,ProductID		INT
	,Rate			MONEY
	,Rate3rd		MONEY
	,Fromdate		SMALLDATETIME
	,Todate			SMALLDATETIME
)
-- ​Pay to Supplier:
--   Credit: 1% of of Licensee Winloss
--   Deposit: 7.5% of Licensee Winloss
INSERT INTO #ChargeInfo
SELECT c.PartyID, c.LicenseeID, c.isDeposit, c.ProductID, c.DI_Rate, 
	CASE WHEN ISNULL(c.isDeposit,0)=1 THEN 0.075 ELSE 0.01 END
, c.Fromdate, c.Todate
FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs,@FromDate,@ToDate,'VS','OA',@ExcludeTest) c

SELECT DISTINCT ExchangeDate, ExchangeId, BaseCurrencyRate AS Rate
INTO #TempExchange
FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

IF @IsConvert = 0 UPDATE #TempExchange SET Rate = 1

;WITH d AS (
	SELECT b.rptDate, b.currencyID, c.PartyID, l.sporttype, b.bettype
		, SUM(CASE
				WHEN @drawfilter IN (2,3) AND b.status = 111 THEN 0.0
				WHEN @drawfilter IN (2,3) AND (b.status = 114 OR b.status = 115) THEN b.Turnover * 0.5
			ELSE b.Turnover END) AS Turnover
		, SUM(-b.Winloss) AS GrossWinloss
		, SUM(-b.Winloss * c.Rate3rd) AS PayToSupplier
		, SUM(-b.Winloss * c.Rate) AS OneworksIncome
		, SUM(CASE WHEN @drawfilter = 2 AND b.status = 111 THEN 0 ELSE BetCount END) AS BetCount
	FROM bodb_licenseereport.dbo.rpt_Betting b WITH ( NOLOCK)
		INNER JOIN #ChargeInfo c ON c.LicenseeID = b.siteID AND b.rptDate BETWEEN c.Fromdate AND c.Todate
		LEFT JOIN dbo.League l WITH (NOLOCK) ON b.LeagueID = l.LeagueID
	WHERE b.rptDate BETWEEN c.Fromdate AND c.Todate
		AND b.status NOT IN (-1, 101, 102, 103)
		AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20))
		AND b.bettype BETWEEN 1201 AND 1299
		AND (@Sporttype = 0 OR ( @Sporttype<>0 AND l.Sporttype = @Sporttype))
		AND (@bettype = 0 OR (b.bettype = @bettype AND @bettype <> 0))
		AND b.customercategory NOT IN (27,28)
	GROUP BY b.rptDate,b.currencyID,c.PartyID,l.sporttype, b.bettype
)
SELECT
	p.PartyName,
	d.rptDate AS WinlostDate,
	d.SportType,
	d.BetType,
	ISNULL(SUM(d.betcount), 0) AS BetCount,
	CAST(ISNULL(SUM(d.turnover * ex.Rate),0) AS MONEY) AS Turnover,
	CAST(ISNULL(SUM(d.GrossWinloss * ex.Rate),0) AS MONEY) AS GrossWinloss,
	CAST(ISNULL(SUM(d.PayToSupplier * ex.Rate),0) AS MONEY) AS PayToSupplier,
	CAST(ISNULL(SUM(d.OneworksIncome * ex.Rate),0) AS MONEY) AS OneworksIncome,
	CAST(ISNULL(SUM((d.OneworksIncome - d.PayToSupplier) * ex.Rate),0) AS MONEY) AS NetIncome
FROM d
	INNER JOIN #TempExchange ex ON d.rptDate = ex.exchangedate and d.currencyID = ex.ExchangeId
	INNER JOIN #Party p ON p.PartyId = d.PartyID
GROUP BY d.sporttype, d.bettype, d.rptDate, p.PartyName
ORDER BY d.rptDate ASC, p.PartyName, d.sporttype, d.bettype

DROP TABLE  #TempExchange
DROP TABLE  #Party
DROP TABLE  #ChargeInfo
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_VirtualSportWinloss] TO [vnteam]
GRANT EXECUTE ON [dbo].[LA_Rpt_VirtualSportWinloss] TO bodbAdminNet
