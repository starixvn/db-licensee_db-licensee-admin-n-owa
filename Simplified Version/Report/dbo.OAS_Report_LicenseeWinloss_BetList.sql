ALTER  PROCEDURE [dbo].[OAS_Report_LicenseeWinloss_BetList]
	@CustID			INT,
	@FromDate		DATETIME,
	@ToDate			DATETIME,
	@MoveBetsDay	SMALLDATETIME,
	@BalanceUpDay	SMALLDATETIME,
	@TotalRows INT=0 OUTPUT,
	@SumWinlost MONEY=0 OUTPUT,
	@SumWinlostUSD MONEY=0 OUTPUT,
	@SumWinlostEUR MONEY=0 OUTPUT,
	@SumLicenseeWL MONEY=0 OUTPUT,
	@SumLicenseeWLUSD MONEY=0 OUTPUT,
	@SumLicenseeWLEUR MONEY=0 OUTPUT,
	@SumComm MONEY=0 OUTPUT,
	@SumCommUSD MONEY=0 OUTPUT,
	@SumCommEUR MONEY=0 OUTPUT,
	@SumPlayerComm    MONEY=0 OUTPUT,
	@SumPlayerCommUSD MONEY=0 OUTPUT,
	@SumPlayerCommEUR MONEY=0 OUTPUT,
	@drawfilter SMALLINT = 1,
	@Language VARCHAR(10) = 'en-us'  
AS

/*
Created: Henry 
Date: 2012-09-26
Task : Betlist for Licensee Winloss Report
DB: DB06.bodb02

Revisions:
Param's Explanation:
	+ @drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)

*/

SET NOCOUNT ON

CREATE TABLE  #BetListByDateMem (
	Sporttype		INT,
	TransID			BIGINT,
	BetID			BIGINT,
	Bettype			INT,
	hdp1			SMALLMONEY, 
	hdp2			SMALLMONEY, 
	Modds			SMALLMONEY,
	OddsType		TINYINT,
	Odds			SMALLMONEY, 
	Stake MONEY, 
	Actual_Stake	MONEY,
	Betteam			NVARCHAR(20),
	Status			NVARCHAR(10),
	RefNO			BIGINT,	
	Transdate		DATETIME,
	Winlostdate		DATETIME,
	Winlost			MONEY,
	LicenseeWL		MONEY,
	comm			MONEY,
	playercomm		MONEY,
	Liveindicator	BIT,
	Livehomescore	SMALLINT,
	Liveawayscore	SMALLINT,
	IP				NVARCHAR(15),
	LeagueID		INT,
	MatchID			INT,
	MatchCode		NVARCHAR(50),
	Race			NVARCHAR(20),
	HomeID			INT,
	AwayID			INT, 	
	Betstatus		NVARCHAR(50),
	isNeutral		BIT,
	virtualrate		float,
	isShowOTExRate	BIT,
	currency INT,
	showtime NVARCHAR(50) -- table - shoe - hand of Live Casino
)

CREATE TABLE  #TempBetList (
	TransID			BIGINT PRIMARY KEY,
	BetID			BIGINT,
	Bettype			INT,
	hdp1			SMALLMONEY, 
	hdp2			SMALLMONEY, 
	Modds			SMALLMONEY,
	OddsType		TINYINT,
	Odds			SMALLMONEY, 
	Stake MONEY, 
	Actual_Stake	MONEY,
	Betteam			NVARCHAR(20),
	Status			NVARCHAR(10),
	RefNO			BIGINT,	
	Transdate		DATETIME,
	Winlostdate		DATETIME,
	Winlost			MONEY,
	LicenseeWL		MONEY,
	comm			MONEY,
	playercomm		MONEY,
	Liveindicator	BIT,
	Livehomescore	SMALLINT,
	Liveawayscore	SMALLINT,
	IP				NVARCHAR(50),
	currency INT,
	MatchID INT
)

declare @fdate DATETIME, @tdate datetime
select @fdate = @FromDate, @tdate = @ToDate

DECLARE @ShowSB BIT

SET @ShowSB = 1

DECLARE	@currency INT 
SELECT	@currency = currency FROM customer (NOLOCK) WHERE custid = @custid

Declare @TempFromDate DATETIME
Declare @TempToDate DATETIME

IF @tdate >= @BalanceUpDay
BEGIN
	IF @fdate < @BalanceUpDay 
		SET @TempFromDate =  @BalanceUpDay
	ELSE
		SET @TempFromDate = @fdate

	--Sport Book
	IF @ShowSB = 1
	BEGIN
		INSERT INTO #BetListByDateMem
			SELECT
				m.Sporttype, 
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				b.hdp1, 
				b.hdp2,
				modds,
				b.OddsType,
				b.Odds,
				b.stake,
				b.actual_stake,  
				b.betteam, --Betteam
				b.status AS Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,			
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake) ,
				comm,
				b.playercomm ,
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				m.LeagueID,
				m.MatchID,	
				m.MatchCode,
				'' AS Race,	
				m.HomeID,
				m.AwayID, 		
				m.Betstatus,
				ISNULL(m.isNeutral, CONVERT(BIT,0)) AS IsNeutral,
				0,0,
				b.currency,
				'' As ShowTime
			FROM
				dbo.bettrans AS b WITH (NOLOCK)		
				INNER JOIN dbo.match AS m WITH (NOLOCK) ON b.matchid=m.matchid
			WHERE
				b.winlostdate BETWEEN @TempFromDate AND @tdate AND
				b.custid=@custid AND
				(b.bettype < 31 OR (b.bettype BETWEEN 121 AND 999 ))  AND
				b.bettype NOT IN (9,29,10)	AND
				b.matchid > 0 AND
				b.statusID IN (111,112,113) AND
				b.tpositiontaking <> 0 --exclude BA tickets
		
		-- Outright
		INSERT INTO #BetListByDateMem
			SELECT
				l.sporttype, --Sporttype
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				0 AS hdp1, 
				0 AS hdp2, 
				modds,
				0 AS OddsType, 
				b.Odds, 
				b.stake,
				b.actual_stake, 
				'' AS Betteam, --Betteam
				b.Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,						
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake),
				comm ,
				b.playercomm , 
				0 AS LiveIndicator , 
				b.LiveHomescore, 
				b.LiveAwayscore,
				b.IP AS IP,
				m.LeagueID,
				m.OrId,--0, --MatchID	
				m.MatchCode,
				m.GroupMatch,--Race
				m.TeamID, --HomeID
				0, --AwayID		
				0, --Betstatus
				CONVERT(BIT,0) AS IsNeutral,
				0,0,
				b.currency,
				'' As ShowTime
			FROM
				dbo.bettrans AS b WITH (NOLOCK)		
				INNER JOIN dbo.Outright AS m WITH (NOLOCK) ON b.matchid=m.orid
				INNER JOIN dbo.League AS l WITH (NOLOCK) ON m.leagueID = l.leagueID 
			WHERE
				b.winlostdate BETWEEN @TempFromDate AND @tdate AND
				b.custid=@custid AND
				b.bettype = 10 AND
				b.statusID IN (111,112,113) AND
				b.tpositiontaking <> 0 --exclude BA tickets
				

		-- Mix Parlay + System Parlay		
		INSERT INTO #BetListByDateMem
			SELECT
				0, --Sporttype
				CASE WHEN bettype <> 29 THEN b.transid
				ELSE CASE WHEN ISNULL(b.BetID,0)=0 THEN b.transid ELSE betid END
				END AS transid,	
				ISNULL(b.BetID,0),
				b.bettype,
				b.hdp1, 
				b.hdp2, 
				modds,
				0 AS OddsType, 
				b.Odds, 
				b.stake,
				b.actual_stake, 
				b.betteam, --Betteam
				b.Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,						
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake) ,
				comm,
				b.playercomm , 
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				0, --LeagueID
				0, --MatchID	
				'',--MatchCode
				'',--Race
				0, --HomeID
				0, --AwayID		
				0, --Betstatus
				CONVERT(BIT,0) AS IsNeutral,
				0,0,
				b.currency,
				'' as ShowTime
			FROM
				dbo.bettrans b WITH (NOLOCK)	
			WHERE
				b.winlostdate BETWEEN @TempFromDate AND @tdate AND
				b.custid=@custid AND
				b.bettype IN (9,29) AND
				b.matchid IN (9,29) AND
				b.statusID IN (111,112,113) AND
				b.tpositiontaking <> 0 --exclude BA tickets			
	END
END

IF @fdate < @BalanceUpDay
BEGIN
	IF @tdate >= DATEADD(dd, -1, @BalanceUpDay)
		SET @TempToDate = DATEADD(dd, -1, @BalanceUpDay)
	ELSE
		SET  @TempToDate = @tdate
		
	--Sport Book
	IF @ShowSB = 1
	BEGIN
		INSERT INTO #BetListByDateMem
			SELECT
				m.Sporttype, 
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				b.hdp1, 
				b.hdp2,
				modds,
				b.Oddstype,
				b.Odds,
				b.stake,
				b.actual_stake,  
				b.betteam, --Betteam
				b.status AS Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,			
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake),
				comm,
				b.playercomm,
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				m.LeagueID,
				m.MatchID,	
				m.MatchCode,
				'' AS Race,	
				m.HomeID,
				m.AwayID, 		
				m.Betstatus,
				ISNULL(m.isNeutral, CONVERT(BIT,0)) AS IsNeutral,
				0,0,
				b.currency,
				'' As ShowTime
			FROM
				bodb_archive.dbo.bettrans_bk AS b WITH (NOLOCK)		
				INNER JOIN bodb_archive.dbo.match_BK AS m WITH (NOLOCK) ON b.matchid=m.matchid  
			WHERE
				b.winlostdate BETWEEN @fdate AND @TempToDate AND
				b.custid=@custid AND
				b.ruben = 1 AND
				b.status NOT IN ('VOID', 'REJECT', 'REFUND') AND 
				(b.bettype < 31 OR (b.bettype BETWEEN 121 AND 999 )) AND
				b.bettype NOT IN (9,29, 10) AND
				b.tpositiontaking <> 0 --exclude BA tickets
				
		
		-- Outright
		INSERT INTO #BetListByDateMem
			SELECT
				l.sporttype, --Sporttype
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				0 AS hdp1, 
				0 AS hdp2, 
				modds,
				0 AS OddsType, 
				b.Odds, 
				b.stake,
				b.actual_stake,  
				'' AS Betteam, --Betteam
				b.Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,						
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake),
				comm,
				b.playercomm, 
				0 AS LiveIndicator , 
				b.LiveHomescore, 
				b.LiveAwayscore,
				b.IP AS IP,
				m.LeagueID,
				m.OrId,--0, --MatchID	
				m.MatchCode,
				m.GroupMatch,--Race
				m.TeamID, --HomeID
				0, --AwayID		
				0, --Betstatus
				CONVERT(BIT,0) AS IsNeutral,
				0,0,
				b.currency,
				'' As ShowTime
			FROM
				bodb_archive.dbo.bettrans_bk  AS b WITH (NOLOCK)		
				INNER JOIN bodb_archive.dbo.Outright_bk AS m WITH (NOLOCK) ON b.matchid=m.orid
				INNER JOIN dbo.League AS l WITH (NOLOCK) ON m.leagueID = l.leagueID
			WHERE
				b.winlostdate BETWEEN @fdate AND @TempToDate AND
				b.custid=@custid AND
				b.ruben = 1 AND
				b.status NOT IN ('VOID', 'REJECT', 'REFUND') AND 
				b.bettype = 10 AND
				b.tpositiontaking <> 0 --exclude BA tickets

		-- Mix Parlay	+ System Parlay	
		INSERT INTO #BetListByDateMem
			SELECT
				0, --Sporttype
				CASE WHEN bettype <> 29 THEN b.transid
				ELSE CASE WHEN ISNULL(b.BetID,0)=0 THEN b.transid ELSE betid END
				END AS transid,	
				ISNULL(b.BetID,0),
				b.bettype,
				b.hdp1, 
				b.hdp2, 
				modds,
				0 AS OddsType, 
				b.Odds, 
				b.stake,
				b.actual_stake,   
				b.betteam, --Betteam
				b.Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,						
				(b.winlost-actual_stake),
				 - (b.winlost-actual_stake) ,
				comm ,
				b.playercomm, 
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				0, --LeagueID
				0, --MatchID	
				'',--MatchCode
				'',--Race
				0, --HomeID
				0, --AwayID		
				0, --Betstatus
				CONVERT(BIT,0) AS IsNeutral,
				0,0,
				b.currency,
				'' As ShowTime
			FROM
				bodb_archive.dbo.bettrans_bk b WITH (NOLOCK)	
			WHERE
				b.winlostdate BETWEEN @fdate AND @TempToDate AND
				b.custid=@custid AND
				b.ruben = 1 AND 
				b.status NOT IN ('VOID', 'REJECT','REFUND') AND
				b.bettype IN (9,29) AND
				--b.matchid = 0
				b.matchid IN (0,9,29) AND --should NOT remove 0 IN archive
				b.tpositiontaking <> 0 --exclude BA tickets
	END	
END



--@currency
SELECT * INTO #TempExchange 
FROM Lrf_f_GetExchangeDaily(@FDate,@TDate)
WHERE exchangeid = @currency

--exclude draw for no draw option (2)
DELETE FROM #BetListByDateMem
WHERE @drawfilter = 2 AND status = 'DRAW' AND ABS(modds) <> 0.25


SELECT 
	@TotalRows = count(transid),
	@SumWinlost=SUM(ISNULL(winlost,0)),
	@SumLicenseeWL=SUM(ISNULL(LicenseeWL,0)),
	@SumComm=SUM(ISNULL(comm,0)) ,
	@SumPlayerComm=SUM(ISNULL(playercomm,0)),
	--USD
	@SumWinlostUSD=SUM(ISNULL(winlost*e.USD,0)),
	@SumLicenseeWLUSD=SUM(ISNULL(LicenseeWL*e.USD,0)),
	@SumCommUSD=SUM(ISNULL(comm*e.USD,0)) ,
	@SumPlayerCommUSD=SUM(ISNULL(Playercomm*e.USD,0)),
	--EUR
	@SumWinlostEUR=SUM(ISNULL(winlost*e.EUR,0)),
	@SumLicenseeWLEUR=SUM(ISNULL(LicenseeWL*e.EUR,0)),
	@SumCommEUR=SUM(ISNULL(comm*e.EUR,0)) ,
	@SumPlayerCommEUR=SUM(ISNULL(playercomm*e.EUR,0))
FROM #BetListByDateMem b
INNER JOIN 
	#TempExchange e 
	ON e.ExchangeDate = b.winlostdate   AND e.exchangeid = b.currency
	
SELECT	d.* , 
		--BASE RM
		d.stake*e.MYR		AS	StakeMYR,
		d.actual_stake*e.MYR		AS	actual_stakeMYR,
		d.winlost*e.MYR			AS	WinlostMYR,
		d.LicenseeWL*e.MYR		AS	LicenseeWLMYR,
		d.comm*e.MYR		AS	commMYR,
		d.playercomm*e.MYR  AS PlayerCommMYR,
		--BASEUSD
		d.stake*e.USD			AS	StakeUSD,
		d.actual_stake*e.USD	AS	actual_stakeUSD,
		d.winlost*e.USD			AS	WinlostUSD,
		d.LicenseeWL*e.USD		AS	LicenseeWLUSD,
		d.comm*e.USD			AS	commUSD,
		d.playercomm*e.USD		AS  playercommUSD,
		--BASEEUR
		d.stake*e.EUR			AS	StakeEUR,
		d.actual_stake*e.EUR	AS	actual_stakeEUR,
		d.winlost*e.EUR			AS	WinlostEUR,
		d.LicenseeWL*e.EUR		AS	LicenseeWLEUR,
		d.comm*e.EUR			AS	commEUR,
		d.playercomm*e.EUR		AS PlayercommEUR

FROM	#BetListByDateMem d 
		INNER JOIN #TempExchange e 
		ON e.ExchangeDate =  d.winlostdate AND e.exchangeid = d.currency
ORDER BY TransID 


DROP TABLE #TempBetList	
DROP TABLE #BetListByDateMem
DROP TABLE #TempExchange

GO
GRANT EXECUTE ON [dbo].[OAS_Report_LicenseeWinloss_BetList] TO [bodbAdminNet]

GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Report_LicenseeWinloss_BetList] TO [vnteam]
 