/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_Rpt_VirtualSportWinloss]
	@PartyIDs				VARCHAR(5500)
	, @FromDate				SMALLDATETIME
	, @ToDate				SMALLDATETIME
	, @SportType			INT			= 0
	, @BetType				INT			= 0
	, @drawfilter			SMALLINT	= 1
	, @IsConvert			BIT			= 1
	, @BaseCurrencyName		VARCHAR(10)	= 'EUR'
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
		- 20171220@Parsons: increase length for variables [#88197]
		- 20180301@Harper: Virtual Sports - Change of commercial terms between company and provider [RedmineID: #91255]
		- 20180327@Harper: Add more Cozni as Parent Licensee [RedmineID: #85681]
		- 20180716@bruce: add new group TEST for credit [#98126]
		- 20180815@Scofield: Remove "Exclude Test Data" checkbox [#98623]

 * Param's Explanation:
 *  - @FromDate   : From date
 *  - @ToDate   : To date
 *  - @Sporttype   : Sporttype
 *  - @BetList:  Bettype offered for Virtual sports (0:All Bettype)
 *  - @drawfilter:  'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only) 
 */

BEGIN

SET NOCOUNT ON	
	
	DECLARE @ChargeInfos AS TABLE (
		PartyID			INT
		,PartyName		VARCHAR(50)
		,ParentID		INT		
		,LicenseeID		INT
		,IsDeposit		INT
		,ProductID		INT
		,Rate			MONEY		
		,Fromdate		SMALLDATETIME
		,Todate			SMALLDATETIME
		)
		
	DECLARE @Charge3rdInfos AS TABLE (
		PartyID			INT	
		,IsDeposit		INT
		,ProductID		INT
		,Rate			MONEY		
		,Fromdate		SMALLDATETIME
		,Todate			SMALLDATETIME
		)	

	-- Region: Charge Info	
	INSERT INTO @ChargeInfos(PartyId, ProductID, LicenseeId, IsDeposit, Rate, Fromdate, Todate)
	(
		SELECT c.PartyID, c.ProductID, c.LicenseeID, c.isDeposit,c.DI_Rate, c.Fromdate, c.Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfoWithCredit(@PartyIDs, @FromDate, @ToDate, 'VS') c 
	)	
	
	DELETE @ChargeInfos
	WHERE IsDeposit = 1 AND Rate = 0	
	
	DECLARE @PartyList AS TABLE (PartyId INT, PartyName	VARCHAR(100), BranchName VARCHAR(100), ParentId	INT)

	INSERT INTO @PartyList (PartyId, PartyName, BranchName, ParentId)
	EXEC bodb_licensee.dbo.LA_PartyListSel
		
	DELETE p
	FROM @PartyList p
	WHERE NOT EXISTS (SELECT 1 FROM @ChargeInfos ci WHERE ci.PartyId = p.PartyId)
			
	UPDATE ci
	SET ci.PartyName = p.PartyName,
		ci.ParentID = p.ParentId
	FROM @ChargeInfos ci
	INNER JOIN @PartyList p ON ci.PartyId = p.PartyId 
	
	-- End region

	-- Region: Charge 3rd
	INSERT INTO @Charge3rdInfos ( PartyID ,IsDeposit ,ProductID ,Rate ,Fromdate ,Todate )	
	(
		SELECT c.PartyID, c.isDeposit, c.ProductID, c.DI_Rate, c.Fromdate, c.Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, 'VS', 'OA') c 
		UNION ALL
		SELECT 999, 0, 5, 0.01, @FromDate, @ToDate
	)	

	-- End Region: Charge 3rd

	-- Region: Get Echange Rate
	SELECT DISTINCT ExchangeDate, ExchangeId, BaseCurrencyRate AS Rate
	INTO #TempExchange
	FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	
	IF @IsConvert = 0 UPDATE #TempExchange SET Rate = 1
	-- End region: Get Exchange Rate

	-- Region: Return Result
	;WITH d AS (
		SELECT b.rptDate, b.currencyID, c.PartyID, c.PartyName, l.sporttype, b.bettype
			, SUM(CASE
					WHEN @drawfilter IN (2,3) AND b.status = 111 THEN 0.0
					WHEN @drawfilter IN (2,3) AND (b.status = 114 OR b.status = 115) THEN b.Turnover * 0.5
				ELSE b.Turnover END) AS Turnover
			, SUM(-b.Winloss) AS GrossWinloss
			, SUM(-b.Winloss * c3.Rate) AS PayToSupplier
			, SUM(-b.Winloss * c.Rate) AS OneworksIncome
			, SUM(CASE WHEN @drawfilter = 2 AND b.status = 111 THEN 0 ELSE BetCount END) AS BetCount
		FROM bodb_licenseereport.dbo.rpt_Betting b WITH ( NOLOCK)
			INNER JOIN @ChargeInfos c ON c.LicenseeID = b.siteID AND b.rptDate BETWEEN c.Fromdate AND c.Todate
			INNER JOIN @Charge3rdInfos c3 ON c3.PartyID = c.ParentID AND b.rptDate BETWEEN c3.Fromdate AND c3.Todate
			LEFT JOIN dbo.League l WITH (NOLOCK) ON b.LeagueID = l.LeagueID
		WHERE b.rptDate BETWEEN @FromDate AND @ToDate
			AND b.status NOT IN (-1, 101, 102, 103)
			AND (b.CurrencyID <> 20)
			AND b.bettype BETWEEN 1201 AND 1299
			AND (@Sporttype = 0 OR ( @Sporttype<>0 AND l.Sporttype = @Sporttype))
			AND (@bettype = 0 OR (b.bettype = @bettype AND @bettype <> 0))
			AND b.customercategory NOT IN (27,28)
		GROUP BY b.rptDate,b.currencyID,c.PartyID,c.PartyName,l.sporttype, b.bettype
	)
	SELECT
		d.PartyName,
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
	GROUP BY d.sporttype, d.bettype, d.rptDate, d.PartyName
	ORDER BY d.rptDate ASC, d.PartyName, d.sporttype, d.bettype
	-- End Region: Return Result

	DROP TABLE  #TempExchange	
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_VirtualSportWinloss] TO [vnteam]
GRANT EXECUTE ON [dbo].[LA_Rpt_VirtualSportWinloss] TO bodbAdminNet
GO