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

	CREATE TABLE #Result (PartyID INT, ReportType VARCHAR(8), TurnOver MONEY, CustomerWinlost MONEY, CommBA MONEY ,CommRB MONEY, Betcount BIGINT, WinningPrize MONEY, LicensingFee MONEY)

	CREATE TABLE #Temp (PartyID INT, Rptdate DATETIME, Currency INT, TurnOver MONEY, Winlost MONEY, CommBA MONEY, CommRB MONEY, WinningPrize MONEY, Betcount BIGINT)

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
		INSERT INTO #Temp (PartyID, Rptdate, Currency, TurnOver, Winlost, CommBA, CommRB, Betcount)
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
			--, 0 AS LicenseeFee
			, SUM(b.CommissionA) AS CommBA
			, 0 AS CommRB
			, SUM(betcount *
					CASE WHEN @drawfilter = 2 AND b.status = 111 THEN 0
						ELSE 1 END) AS BetCount
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
		INSERT INTO #Temp (PartyID, rptDate, Currency, CommBA, CommRB, Betcount, TurnOver, Winlost, WinningPrize)
		(
			SELECT tp.PartyID, b.rptDate, b.CurrencyID,0,0
				, SUM(b.BetCount)
				, SUM(b.Turnover)
				, SUM(CASE WHEN b.Bettype <> @PromotionPrize THEN ISNULL(b.MemberWL, 0) ELSE 0 END) AS Winlost
				, SUM(CASE WHEN b.Bettype = @PromotionPrize THEN ISNULL(b.MemberWL, 0) ELSE 0 END)  AS WinningPrize
				FROM bodb_LicenseeReport..rpt_BettingByProduct b WITH (NOLOCK)
					INNER JOIN (SELECT DISTINCT PartyID, LicenseeID FROM @tmpParty) tp ON tp.LicenseeID = b.SiteID
				WHERE b.ProductID = 32
					AND b.rptDate BETWEEN @FromDate AND @ToDate
					AND (b.CurrencyID <> 20)
					AND (@Currency = 0 OR b.CurrencyID = @Currency)  
					AND b.[StatusId] NOT IN (-1, 101, 102, 103)
				GROUP BY tp.PartyID, b.rptDate, b.CurrencyID
		)
	END

	IF @ProductCode NOT IN('BA', 'PP')
	BEGIN
		INSERT INTO #Temp (PartyID, Rptdate, Currency, TurnOver, Winlost, CommBA, CommRB, Betcount)
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
			--, 0 AS LicenseeFee
			, 0 AS CommBA
			, SUM(CASE WHEN b.bettype BETWEEN 31 AND 33 THEN b.CommissionA ELSE 0 END ) AS CommRB
			, SUM(b.betcount *
					CASE WHEN @drawfilter = 2 AND b.Status = 111 THEN 0
					ELSE 1 END) AS BetCount
			FROM bodb_LicenseeReport.dbo.rpt_Betting b WITH ( NOLOCK )
			INNER JOIN(
					SELECT DISTINCT PartyID, LicenseeID--, Bettype
					FROM @tmpParty
			)tp ON b.SiteID = tp.LicenseeID-- AND b.Bettype = tp.Bettype
			WHERE  b.rptDate BETWEEN @Fromdate AND @ToDate
			AND b.Bettype IN (SELECT Bettype FROM @Bettype)
			AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
			AND (b.CurrencyID <> 20)
			AND b.status NOT IN (-1, 101, 102, 103)
			AND b.customercategory NOT IN (27, 28)
			GROUP BY PartyID, b.rptDate, b.currencyID
		)
	END

	INSERT INTO #Result (PartyID, ReportType, TurnOver, CustomerWinlost, CommBA, CommRB, Betcount, WinningPrize, LicensingFee)
	SELECT b.PartyID
		, CONVERT(VARCHAR(6),b.rptDate,112)
		, SUM(TurnOver * e.Rate)	AS Turnover
		, SUM((Winlost + ISNULL(WinningPrize, 0)) * e.Rate)	AS CustomerWinlost
		, SUM(CommBA * e.Rate) AS CommBA
		, SUM(CommRB * e.Rate) AS CommRB
		, SUM(Betcount) AS Betcount
		, SUM(ISNULL(WinningPrize, 0) * e.Rate) AS WinningPrize
		, SUM((-b.Winlost * ISNULL(p.Rate,0)) * e.Rate) AS LicensingFee
	FROM #Temp b
	INNER JOIN #Exchange e  ON e.ExchangeDate = b.Rptdate AND e.ExchangeId = b.Currency
	INNER JOIN  (
		SELECT DISTINCT PartyID, FromDate, ToDate, Rate
		FROM @tmpParty
	) p ON b.PartyID = p.PartyID AND b.rptDate BETWEEN p.Fromdate AND p.Todate
	GROUP BY CONVERT(VARCHAR(6), b.rptDate, 112), b.PartyID
	
	UPDATE #Result
	SET LicensingFee = 0
	WHERE LicensingFee < 0

	-------------------------final select -------------------------------
	SELECT CAST((ReportType + '01') AS DATE) AS [DateTime]
		, SUM(TurnOver) AS TurnOver
		, SUM(CustomerWinlost) AS CustomerWinlost
		, SUM(CommBA) AS AmtDueToBA
		, SUM(CommRB) AS AmtDueToRB
		, SUM(Betcount) AS BetCount
		, SUM(LicensingFee - WinningPrize) AS LicensingFee
	FROM #Result
	GROUP BY ReportType
	ORDER BY ReportType ASC

	DROP TABLE #Result
	DROP TABLE #Exchange
	DROP TABLE #Temp
END
GO