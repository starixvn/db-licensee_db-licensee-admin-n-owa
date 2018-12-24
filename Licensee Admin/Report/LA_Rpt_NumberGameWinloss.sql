/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_Rpt_NumberGameWinloss]
	 @PartyIDs				VARCHAR(5500)
	, @FromDate				SMALLDATETIME
	, @ToDate				SMALLDATETIME
	, @Currency				INT				= 0
	, @drawfilter			SMALLINT		= 0
	, @IsConvert			BIT				= 1
	, @BaseCurrencyName		VARCHAR(10)		= 'EUR'
AS

/*
 * Created by : [20140904@Florent.Nguyen]
 * Task  : Get Number Game Winloss
 * DB   : DB052.bodb02
 * Revisions :
	- 20141111@Florent: using new OAS_ChargeInfo structure and use unique formula
	- 20150703@Florent: add GBP
	- 20161022@Jim:move table to bodb_licenseereport [RedmineID :#60449]
	- 20170621@Bruce: include paytosupplier & netincome [#78398]
	- 20171220@Parsons: increase length for variables [#88197]
	- 20180716@bruce: add new group TEST for credit [#98126]
	- 20180815@Scofield: Remove "Exclude Test Data" checkbox [#98623]
	- 20181224@Bruce: include happy 5 [#105723]
	
 * Param's Explanation:
 *
 */

BEGIN
	SET NOCOUNT ON

	CREATE TABLE #Party (PartyId INT,PartyName VARCHAR(100),BrandName VARCHAR(100),ParentId INT)
	INSERT INTO #Party EXEC bodb_licensee.dbo.LA_PartyListSel

	CREATE TABLE #ChargeRate (
		PartyID			INT
		,LicenseeID		INT
		,isDeposit		INT
		,ProductID		INT
		,Rate			MONEY
		,Rate3rd		MONEY
		,Fromdate		SMALLDATETIME
		,Todate			SMALLDATETIME
	)
	-- ​Pay to Supplier: equals 40% of [Licensing Fee]
	INSERT INTO #ChargeRate
	SELECT c.PartyID, c.LicenseeID, c.isDeposit, c.ProductID, c.DI_Rate, 0.4, c.Fromdate, c.Todate
	FROM bodb_licensee.dbo.LA_f_ChargeInfoWithCredit(@PartyIDs, @FromDate, @ToDate, 'NG') c

	SELECT DISTINCT ExchangeDate, ExchangeId, BaseCurrencyRate AS Rate
	INTO #Exchange
	FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	IF @IsConvert = 0 UPDATE #Exchange SET Rate = 1

	;WITH re AS (
		SELECT lr.PartyID,
			DATEADD(MONTH, DATEDIFF(MONTH, 0, b.rptDate), 0) AS WinlostDate,
			SUM(e.Rate * CASE
				WHEN @drawfilter IN (2, 3) AND b.status = 111 THEN 0
				WHEN @drawfilter IN (2, 3) AND (b.status = 114 OR b.status = 115) THEN 0.5 * b.Turnover
			ELSE b.Turnover END) AS TurnOver,
			SUM(b.Winloss * e.Rate) AS MemberWinloss,
			SUM(-b.Winloss * lr.Rate * lr.Rate3rd * e.Rate) AS PayToSupplier,
			SUM(-b.Winloss * lr.Rate * e.Rate) AS OneworksRevenue,
			SUM(CASE WHEN @drawfilter = 2 AND b.status = 111 THEN 0 ELSE b.BetCount END) AS BetCount
		FROM bodb_licenseereport.dbo.rpt_Betting b WITH (NOLOCK)
			INNER JOIN bodb_licensee.dbo.LA_f_BettypeProductMapping(0, 'NG') bt ON bt.Bettype = b.Bettype
			INNER JOIN #ChargeRate lr ON b.SiteID = lr.LicenseeID AND b.rptDate BETWEEN lr.FromDate AND lr.ToDate
			INNER JOIN #Exchange e ON b.CurrencyID = e.ExchangeId AND b.rptDate = e.ExchangeDate
		WHERE b.rptDate BETWEEN lr.FromDate AND lr.ToDate
			AND b.status NOT IN (-1, 101, 102, 103)
			AND (b.CurrencyID <> 20)
			AND b.customercategory NOT IN (27,28)
		GROUP BY DATEADD(MONTH, DATEDIFF(MONTH, 0, b.rptDate), 0),lr.PartyID
	)
	SELECT p.PartyName,
		re.Winlostdate,
		re.BetCount,
		CAST(re.Turnover AS MONEY) AS Turnover,
		CAST(re.MemberWinloss AS MONEY) AS MemberWinloss,
		CAST((CASE WHEN -re.MemberWinloss < 0 THEN 0 ELSE re.PayToSupplier END) AS MONEY) AS PayToSupplier,
		CAST((CASE WHEN -re.MemberWinloss < 0 THEN 0 ELSE re.OneworksRevenue - re.PayToSupplier END) AS MONEY) AS NetIncome,
		CAST((CASE WHEN -re.MemberWinloss < 0 THEN 0 ELSE -re.MemberWinloss END) AS MONEY) AS LicenseeWinloss,
		CAST((CASE WHEN re.OneworksRevenue < 0 THEN 0 ELSE re.OneworksRevenue END) AS MONEY) AS OneworksRevenue
	FROM re INNER JOIN #Party p ON re.PartyID = p.PartyID
	ORDER BY re.Winlostdate

	DROP TABLE	#Party
	DROP TABLE	#Exchange
	DROP TABLE	#ChargeRate
END
GO
