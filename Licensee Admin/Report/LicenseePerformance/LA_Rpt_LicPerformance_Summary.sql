/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicPerformance_Summary]
	 @PartyIDs			VARCHAR(4000)	= ''
	, @Currency			INT				= 0
	, @FromDate			SMALLDATETIME
	, @ToDate			SMALLDATETIME
	, @ProductCode		VARCHAR(200)
	, @drawfilter		SMALLINT		= 1
	, @MoveBetsDay		SMALLDATETIME	= ''
	, @IsConvert		BIT				= 0
	, @BaseCurrencyName	VARCHAR(10)		= 'GBP'
WITH RECOMPILE
AS
/*	Created by: 20140929@Florent
	Original: OA_Rpt_LicPerformance_Summary
	Task : LicenseeAdmin - Get Licensee Perfomance Summary Report
     DB: DB052.bodb02

    Revisions:
	   - 20141223@Florent: remove un-use code and enhance
	   - 20150703@Florent: add GBP
	   - 20161022@Jim:move table to bodb_licenseereport [RedmineID :#60449]
	   - 20171205@Bruce: fix partyid length [#87723]
	   - 20171219@Bruce: increase length for variables [#88197]
	   - 20180716@bruce: add new group TEST for credit [#98126]
	   - 20180815@Scofield: Remove "Exclude Test Data" checkbox [#98623]
	   - 20190412@Parsons: Integrate-PP-Promotion-Prize [#109014]
	   - 20191205@Mason: PP tournament [#123958]
	   - 20200217@Mason: Set billing term by currency [#120005]
	   - 20200625@Mason: Keep Negative SB Licensing Fee for 2 special licensees 9wickets, 9Wsports [#136334]
	   - 20200629@Parsons: Enhance loading time for Licensee Performance report [#136341]
	   - 20200820@Parsons: Implement PP JP Changes In Reports Phase 2 [#139055]
	   - 20201026@Happy: Arcadia Gaming Add Bonus [#143597]
	   - 20201113@Parsons: Changing OddsSpread for licensee [#142345]

	   - 20201014@Happy: Saba.club - Offer Freebet tickets [#141423]
	Param's Explanation:
	  + @PartyIDs : a string of list PartyID, separated by ','
	  + @Currency : 0-All Currencies
	  + @drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @CurrencyTest INT = 20
	DECLARE @Bettype TABLE(Bettype INT, ProductID INT)
	INSERT INTO @Bettype
	SELECT Bettype, ProductID
	FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0, @ProductCode)

	DECLARE @tmpParty TABLE(ChargeId INT, PartyID INT, LicenseeID INT, IsDeposit INT, ProductID INT
						, Rate MONEY, AffectedDate SMALLDATETIME, Fromdate SMALLDATETIME, Todate SMALLDATETIME)
	INSERT INTO @tmpParty(ChargeId, PartyID, LicenseeID, IsDeposit, ProductID, Rate, AffectedDate, FromDate, ToDate)
	SELECT DISTINCT ChargeId, PartyID, LicenseeID, IsDeposit, ProductID, DI_Rate, AffectedDate, Fromdate, Todate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCode, 'OA', 1)

	CREATE TABLE #Result (PartyID INT, ReportType VARCHAR(8), TurnOver MONEY, CustomerWinlost MONEY, CommBA MONEY , Betcount BIGINT, LicensingFee MONEY)

	CREATE TABLE #Temp (PartyID INT, Rptdate DATETIME, Currency INT, TurnOver MONEY, Winlost MONEY, CommBA MONEY, Betcount BIGINT, LicensingFee MONEY)

	CREATE TABLE #Exchange (ExchangeDate SMALLDATETIME, ExchangeId INT, Rate FLOAT)
	INSERT INTO #Exchange(ExchangeDate, ExchangeId, Rate)
	SELECT DISTINCT ExchangeDate, ExchangeId, BaseCurrencyRate
	FROM dbo.LA_f_ExchangeDailySel(@Fromdate, @ToDate, @BaseCurrencyName)

	IF (@isconvert = 0)
	BEGIN
		UPDATE #Exchange
		SET Rate = 1
	END

	IF @ProductCode = 'BA'
	BEGIN
		INSERT INTO #Temp (PartyID, Rptdate, Currency, TurnOver, Winlost, CommBA, Betcount, LicensingFee)
		(
			SELECT PartyID, b.rptDate , b.currencyID
			, SUM(b.turnover *
				CASE WHEN @drawfilter IN (2,3) THEN
						CASE WHEN b.status = 111  THEN 0
							WHEN b.status IN (114, 115) THEN 0.5
							ELSE 1 END
						ELSE 1 END
				) TurnOver
			, SUM(b.winloss) Winloss
			, SUM(b.CommissionA) AS CommBA
			, SUM(betcount *
					CASE WHEN @drawfilter = 2 AND b.status = 111 THEN 0
						ELSE 1 END) AS BetCount
			,0
			FROM bodb_LicenseeReport.dbo.rpt_Betting_BA b WITH (NOLOCK)
			INNER JOIN(SELECT DISTINCT PartyID, LicenseeID, Fromdate, Todate FROM @tmpParty)tp ON b.SiteID = tp.LicenseeID AND b.rptDate BETWEEN tp.Fromdate AND tp.Todate
			WHERE b.rptDate BETWEEN @FromDate AND @ToDate
					AND b.Bettype IN (SELECT Bettype FROM @Bettype)
					AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
					AND (b.CurrencyID <> @CurrencyTest)
					AND b.status NOT IN (-1, 101, 102, 103)
			GROUP BY PartyID, b.rptDate, currencyID
		)
	END

	IF @ProductCode = 'PP'
	BEGIN		
		DECLARE @PP_Contribution SMALLINT = 4297
		INSERT INTO #Temp (PartyID, rptDate, Currency, CommBA, Betcount, TurnOver, Winlost, LicensingFee)
		(
			SELECT tp.PartyID, b.rptDate, b.CurrencyID,0
				, SUM(ISNULL(b.betcount, 0) * CASE WHEN (@drawfilter = 2 AND b.[StatusId] = 111) OR b.Bettype = @PP_Contribution THEN 0 ELSE 1 END) BetCount
				, SUM(ISNULL(b.turnover, 0) * CASE WHEN (@drawfilter IN (2, 3) AND b.[StatusId] = 111) OR b.Bettype = @PP_Contribution THEN 0 ELSE 1 END) TurnOver
				, SUM(CASE WHEN b.Bettype = @PP_Contribution THEN 0 ELSE ISNULL(b.MemberWL, 0) END) Winlost
				, SUM((ISNULL(- b.MemberWL, 0) - CASE WHEN b.Bettype = @PP_Contribution THEN ISNULL(-b.GrossWL, 0) ELSE 0 END) 
								* ISNULL(cr.Rate, tp.Rate)) LicensingFee
				FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
					INNER JOIN (SELECT DISTINCT ChargeId, PartyID, LicenseeID, Rate, Fromdate, Todate FROM @tmpParty) tp ON tp.LicenseeID = b.SiteID AND b.rptDate BETWEEN tp.Fromdate AND tp.Todate
					LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = tp.ChargeId AND cr.CurrencyID = b.CurrencyId
					LEFT JOIN bodb_licensee.dbo.LA_f_ExcludedBettypeListSel('','4297') eb ON b.Bettype = eb.BettypeID
				WHERE b.ProductID = 32
					AND b.rptDate BETWEEN @FromDate AND @ToDate
					AND (b.CurrencyID <> @CurrencyTest)
					AND (@Currency = 0 OR b.CurrencyID = @Currency)  
					AND b.customercategory NOT IN (27, 28)
					AND b.[StatusId] NOT IN (-1, 101, 102, 103)
					AND eb.BettypeID IS NULL
				GROUP BY tp.PartyID, b.rptDate, b.CurrencyID
		)
	END

	IF @ProductCode = 'SB'
	BEGIN
		DECLARE @SB_AdjustedOdds SMALLINT = 999
		;WITH cte_SBData AS 
		(
			SELECT ci.PartyID, b.rptDate, b.CurrencyID,0 CommBA
				, SUM(ISNULL(b.betcount, 0) * CASE WHEN (@drawfilter = 2 AND b.[StatusId] = 111) OR b.Bettype = @SB_AdjustedOdds THEN 0 ELSE 1 END) BetCount
				, SUM(ISNULL(b.turnover, 0) * CASE WHEN (@drawfilter IN (2, 3) AND b.[StatusId] = 111) OR b.Bettype = @SB_AdjustedOdds THEN 0 ELSE 1 END) TurnOver
				, SUM(CASE WHEN b.Bettype = @SB_AdjustedOdds THEN 0 ELSE ISNULL(b.MemberWL, 0) END) Winlost
				, SUM(CASE WHEN b.Bettype = @SB_AdjustedOdds THEN 0 ELSE ISNULL(-b.MemberWL, 0) END * ISNULL(cr.Rate, ci.Rate)) AS LicencingFeeAdjustedOdds
				, SUM(CASE WHEN b.Bettype = @SB_AdjustedOdds THEN ISNULL(-b.GrossWL, 0) ELSE 0 END) AS OddsSpreadCost
				FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
					INNER JOIN (SELECT DISTINCT ChargeId, PartyID, LicenseeID, Rate, Fromdate, Todate FROM @tmpParty) ci ON ci.LicenseeID = b.SiteID AND b.rptDate BETWEEN ci.Fromdate AND ci.Todate
					LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.ChargeId AND cr.CurrencyID = b.CurrencyId
				WHERE b.ProductID = 0
					AND b.rptDate BETWEEN @FromDate AND @ToDate
					AND (b.CurrencyID <> @CurrencyTest)
					AND (@Currency = 0 OR b.CurrencyID = @Currency)  
					AND b.customercategory NOT IN (27, 28)
					AND b.[StatusId] NOT IN (-1, 101, 102, 103)
				GROUP BY ci.PartyID, b.rptDate, b.CurrencyID
		)
		INSERT INTO #Temp (PartyID, rptDate, Currency, CommBA, Betcount, TurnOver, Winlost, LicensingFee)
		SELECT PartyID, rptDate, CurrencyID, 0, BetCount, TurnOver, Winlost, LicencingFeeAdjustedOdds + OddsSpreadCost
		FROM cte_SBData 
	END

	IF @ProductCode NOT IN('BA', 'PP', 'SB')
	BEGIN
		INSERT INTO #Temp (PartyID, Rptdate, Currency, TurnOver, Winlost, CommBA, Betcount, LicensingFee)
		(
			SELECT PartyID, b.rptDate, b.currencyID
			, SUM(b.turnover
				* CASE 
						WHEN @drawfilter IN (2, 3) THEN
							CASE WHEN b.StatusId = 111  THEN 0
								 WHEN b.StatusId IN (114, 115) THEN 0.5
							ELSE 1 END
						ELSE 1 END
				) TurnOver
			, SUM(b.MemberWL) AS Winlost
			, 0 AS CommBA
			, SUM(b.betcount *
					CASE WHEN @drawfilter = 2 AND b.StatusId = 111 THEN 0
					ELSE 1 END) AS BetCount
			, SUM(-b.MemberWL * ISNULL(cr.Rate, tp.Rate)) AS LicensingFee
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH ( NOLOCK )
			INNER JOIN @tmpParty tp ON b.SiteID = tp.LicenseeID	AND b.ProductID = tp.ProductID AND b.rptDate BETWEEN tp.Fromdate AND tp.Todate
			LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = tp.ChargeId AND cr.CurrencyID = b.CurrencyID
			LEFT JOIN bodb_licensee.dbo.LA_f_ExcludedBettypeListSel('34','') eb ON b.Bettype = eb.BettypeID
			WHERE  b.rptDate BETWEEN @Fromdate AND @ToDate
			AND (@Currency = 0 OR b.CurrencyID = @Currency)
			AND (b.CurrencyID <> @CurrencyTest)
			AND b.StatusId NOT IN (-1, 101, 102, 103)
			AND b.customercategory NOT IN (27, 28)
			AND eb.BettypeID IS NULL
			GROUP BY PartyID, b.rptDate, b.currencyID
		)
	END

	INSERT INTO #Result (PartyID, ReportType, TurnOver, CustomerWinlost, CommBA, Betcount, LicensingFee)
	SELECT b.PartyID
		, CONVERT(VARCHAR(6),b.rptDate,112)
		, SUM(TurnOver * e.Rate)				AS Turnover
		, SUM(Winlost * e.Rate)					AS CustomerWinlost
		, SUM(CommBA * e.Rate)					AS CommBA
		, SUM(Betcount)							AS Betcount
		, SUM(b.LicensingFee * e.Rate)			AS LicensingFee
	FROM #Temp b
	INNER JOIN #Exchange e  ON e.ExchangeDate = b.Rptdate AND e.ExchangeId = b.Currency
	INNER JOIN @tmpParty p  ON b.PartyID = p.PartyID AND b.rptDate BETWEEN p.Fromdate AND p.Todate
	GROUP BY CONVERT(VARCHAR(6), b.rptDate, 112), b.PartyID
	
	UPDATE #Result
	SET LicensingFee = 0
	WHERE LicensingFee < 0 AND PartyID NOT IN (316, 459) -- 9wickets, 9Wsports only for SB

	-------------------------final select -------------------------------
	SELECT CAST((ReportType + '01') AS DATE)	AS [DateTime]
		, SUM(TurnOver)							AS TurnOver
		, SUM(CustomerWinlost)					AS CustomerWinlost
		, SUM(CommBA)							AS AmtDueToBA
		, SUM(Betcount)							AS BetCount
		, SUM(LicensingFee)						AS LicensingFee
	FROM #Result
	GROUP BY ReportType
	ORDER BY ReportType ASC

	DROP TABLE #Result
	DROP TABLE #Exchange
	DROP TABLE #Temp
END
GO