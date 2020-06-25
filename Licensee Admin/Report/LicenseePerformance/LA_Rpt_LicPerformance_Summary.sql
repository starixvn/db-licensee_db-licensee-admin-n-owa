/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicPerformance_Summary]
	 @PartyIDs			VARCHAR(4000)	= ''
	, @Currency			INT				= 0
	, @FromDate			SMALLDATETIME
	, @ToDate			SMALLDATETIME
	, @ProductCode		VARCHAR(200)
	, @ReportType		TINYINT			= 2
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

	Param's Explanation:
	  + @PartyIDs : a string of list PartyID, separated by ','
	  + @Currency : 0-All Currencies
	  + @ReportType: 1-Daily; 2-Monthly
	  + @drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @BettypeID : 0-selected all bettype
*/
BEGIN
	SET NOCOUNT ON

	SET @ReportType = 2 -- only allow monthly
	DECLARE @Bettype TABLE(Bettype INT, ProductID INT)
	INSERT INTO @Bettype
	SELECT Bettype, ProductID
	FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0, @ProductCode)

	DECLARE @tmpParty TABLE(ChargeId INT, PartyID INT, LicenseeID INT, IsDeposit INT, ProductID INT
						, Rate MONEY, AffectedDate SMALLDATETIME, Fromdate SMALLDATETIME, Todate SMALLDATETIME)
	INSERT INTO @tmpParty(ChargeId, PartyID, LicenseeID, IsDeposit, ProductID, Rate, AffectedDate, FromDate, ToDate)
	SELECT DISTINCT ChargeId, PartyID, LicenseeID, IsDeposit, ProductID, DI_Rate, AffectedDate, Fromdate, Todate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCode, 'OA', 1)

	CREATE TABLE #Result (PartyID INT, ReportType VARCHAR(8), TurnOver MONEY, CustomerWinlost MONEY, CommBA MONEY ,CommRB MONEY, Betcount BIGINT, LicensingFee MONEY)

	CREATE TABLE #Temp (PartyID INT, Rptdate DATETIME, Currency INT, TurnOver MONEY, Winlost MONEY, CommBA MONEY, CommRB MONEY, Betcount BIGINT, LicensingFee MONEY)

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
		INSERT INTO #Temp (PartyID, Rptdate, Currency, TurnOver, Winlost, CommBA, CommRB, Betcount, LicensingFee)
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
			, 0 AS CommRB
			, SUM(betcount *
					CASE WHEN @drawfilter = 2 AND b.status = 111 THEN 0
						ELSE 1 END) AS BetCount
			,0
			FROM bodb_LicenseeReport.dbo.rpt_Betting_BA b WITH (NOLOCK)
			INNER JOIN(
					SELECT DISTINCT PartyID, LicenseeID
					FROM @tmpParty
			)tp ON b.SiteID = tp.LicenseeID
			WHERE b.rptDate BETWEEN @FromDate AND @ToDate
			AND b.Bettype IN (SELECT Bettype FROM @Bettype)
			AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
			AND (b.CurrencyID <> 20)
			AND b.status NOT IN (-1, 101, 102, 103)
			GROUP BY PartyID, b.rptDate, currencyID
		)
	END

	IF @ProductCode = 'PP'
	BEGIN		
		DECLARE @PromotionPrize SMALLINT = 4300
		DECLARE @PPTournament SMALLINT = 4299
		INSERT INTO #Temp (PartyID, rptDate, Currency, CommBA, CommRB, Betcount, TurnOver, Winlost, LicensingFee)
		(
			SELECT tp.PartyID, b.rptDate, b.CurrencyID,0,0
				, SUM(ISNULL(b.betcount, 0) * CASE WHEN @drawfilter = 2 AND b.[StatusId] = 111 THEN 0 ELSE 1 END) AS BetCount
				, SUM(ISNULL(b.turnover, 0) * CASE WHEN @drawfilter IN (2, 3) AND b.[StatusId] = 111 THEN 0 ELSE 1 END) AS TurnOver
				, SUM(ISNULL(b.MemberWL, 0)) as Winlost
				, SUM(ISNULL(- b.MemberWL, 0) * ISNULL(cr.Rate, tp.Rate)) AS LicensingFee
				FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
					INNER JOIN (SELECT DISTINCT ChargeId, PartyID, LicenseeID, Rate FROM @tmpParty) tp ON tp.LicenseeID = b.SiteID
					LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = tp.ChargeId AND cr.CurrencyID = b.CurrencyId
				WHERE b.ProductID = 32
					AND b.rptDate BETWEEN @FromDate AND @ToDate
					AND (b.CurrencyID <> 20)
					AND (@Currency = 0 OR b.CurrencyID = @Currency)  
					AND b.customercategory NOT IN (27, 28)
					AND b.[StatusId] NOT IN (-1, 101, 102, 103)
					AND b.Bettype NOT IN(@PPTournament, @PromotionPrize)
				GROUP BY tp.PartyID, b.rptDate, b.CurrencyID
		)
	END

	IF @ProductCode NOT IN('BA', 'PP')
	BEGIN
		INSERT INTO #Temp (PartyID, Rptdate, Currency, TurnOver, Winlost, CommBA, CommRB, Betcount, LicensingFee)
		(
			SELECT PartyID, b.rptDate, b.currencyID
			, SUM(b.turnover
				* CASE WHEN b.bettype = 33 AND b.Status IN (114, 115) THEN 0.5 ELSE 1 END
				* CASE WHEN @drawfilter IN (2, 3) THEN
						CASE WHEN b.Status = 111  THEN 0
							WHEN b.Status IN (114, 115) AND b.Bettype != 33 THEN 0.5
							ELSE 1 END
						ELSE 1 END
				) TurnOver
			, SUM(b.winloss) AS Winlost
			, 0 AS CommBA
			, SUM(CASE WHEN b.bettype BETWEEN 31 AND 33 THEN b.CommissionA ELSE 0 END ) AS CommRB
			, SUM(b.betcount *
					CASE WHEN @drawfilter = 2 AND b.Status = 111 THEN 0
					ELSE 1 END) AS BetCount
			, SUM(-b.WinLoss * ISNULL(cr.Rate, tp.Rate)) AS LicensingFee
			FROM bodb_LicenseeReport.dbo.rpt_Betting b WITH ( NOLOCK )
			INNER JOIN(
					SELECT DISTINCT ChargeId, PartyID, LicenseeID, Rate--, Bettype
					FROM @tmpParty
			)tp ON b.SiteID = tp.LicenseeID-- AND b.Bettype = tp.Bettype
			LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = tp.ChargeId AND cr.CurrencyID = b.CurrencyID
			WHERE  b.rptDate BETWEEN @Fromdate AND @ToDate
			AND b.Bettype IN (SELECT Bettype FROM @Bettype)
			AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
			AND (b.CurrencyID <> 20)
			AND b.status NOT IN (-1, 101, 102, 103)
			AND b.customercategory NOT IN (27, 28)
			GROUP BY PartyID, b.rptDate, b.currencyID
		)
	END

	INSERT INTO #Result (PartyID, ReportType, TurnOver, CustomerWinlost, CommBA, CommRB, Betcount, LicensingFee)
	SELECT b.PartyID
		, CONVERT(VARCHAR(6),b.rptDate,112)
		, SUM(TurnOver * e.Rate)	AS Turnover
		, SUM(Winlost * e.Rate)	AS CustomerWinlost
		, SUM(CommBA * e.Rate) AS CommBA
		, SUM(CommRB * e.Rate) AS CommRB
		, SUM(Betcount) AS Betcount
		, SUM(b.LicensingFee * e.Rate) AS LicensingFee
	FROM #Temp b
	INNER JOIN #Exchange e  ON e.ExchangeDate = b.Rptdate AND e.ExchangeId = b.Currency
	INNER JOIN  (
		SELECT DISTINCT PartyID, FromDate, ToDate, Rate
		FROM @tmpParty
	) p ON b.PartyID = p.PartyID AND b.rptDate BETWEEN p.Fromdate AND p.Todate
	GROUP BY CONVERT(VARCHAR(6), b.rptDate, 112), b.PartyID
	
	UPDATE #Result
	SET LicensingFee = 0
	WHERE LicensingFee < 0 AND PartyID NOT IN (316, 459) -- 9wickets, 9Wsports only for SB

	-------------------------final select -------------------------------
	SELECT CAST((ReportType + '01') AS DATE) AS [DateTime]
		, SUM(TurnOver) AS TurnOver
		, SUM(CustomerWinlost) AS CustomerWinlost
		, SUM(CommBA) AS AmtDueToBA
		, SUM(CommRB) AS AmtDueToRB
		, SUM(Betcount) AS BetCount
		, SUM(LicensingFee) AS LicensingFee
	FROM #Result
	GROUP BY ReportType
	ORDER BY ReportType ASC

	DROP TABLE #Result
	DROP TABLE #Exchange
	DROP TABLE #Temp
END
GO