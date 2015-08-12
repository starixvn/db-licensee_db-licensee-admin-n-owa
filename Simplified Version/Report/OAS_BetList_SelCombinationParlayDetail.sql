ALTER  PROCEDURE [dbo].[OAS_BetList_SelCombinationParlayDetail]
	@transid		BIGINT = 0,
	@Refno BIGINT,
	@betid			BIGINT = 0,
	@custid INT,
	@MoveBetsDay SMALLDATETIME,
	@BalanceUpDay SMALLDATETIME,
	@Outstanding MONEY =0 OUTPUT,
	@OutstandingUSD MONEY =0 OUTPUT,
	@OutstandingEUR MONEY =0 OUTPUT,
	@OutstandingMYR MONEY =0 OUTPUT
	
 AS
/*
Created: Francis@20140120
Task : get combination mix parlay tickets (cloned from Lrf_BetList_SelCombinationParlayDetail to use for OWA)
DB: DB052.bodb02
Original: Lrf_BetList_SelCombinationParlayDetail

Revisions:    
	- 20140120@Francis: Remove restriction of LicenseeUsers permission (by currency)
*/
SET NOCOUNT ON

DECLARE @Today SMALLDATETIME 
SELECT @Today = CONVERT(VARCHAR(10), CURRENT_TIMESTAMP, 120)
DECLARE @Fromdate DATETIME
DECLARE @Todate DATETIME 

DECLARE @currency INT
DECLARE @USD float, @EUR float, @MYR float


DECLARE @tmpBettrans AS TABLE(
			transid		BIGINT,
			transdate	DATETIME,
			refno		BIGINT, 
			winlostdate	SMALLDATETIME,
			odds		SMALLMONEY, 			
			stake		MONEY, 
			actual_stake MONEY, 
			winlost		MONEY, 
			status		VARCHAR(20),
			betteam		VARCHAR(20), 
			IP			VARCHAR(40), 
			spositiontaking SMALLMONEY, 
			mpositiontaking SMALLMONEY, 
			apositiontaking SMALLMONEY, 
			swinlost	MONEY, 
			mwinlost	MONEY, 
			awinlost	MONEY, 
			sdiscount	SMALLMONEY, 
			adiscount	SMALLMONEY, 
			discount	SMALLMONEY, 
			scomm		MONEY, 
			acomm		MONEY, 
			comm		MONEY,
			playercomm  MONEY,
			--for generating combination parlays if not in BetParlayResult
			[N] [tinyint] , -- total selection (match)
			[cnt] [smallint] , -- total sub-ticket count
			[bitmap] [smallint] -- bitmap to identify which parlay set is choosen			
			)
DECLARE @parlay_base AS TABLE(
			transid		BIGINT,
			refno		BIGINT,
			winlostdate	SMALLDATETIME,
			bettype		INT,
			homeid		INT,
			awayid		INT,
			hdp1		SMALLMONEY,
			hdp2		SMALLMONEY,
			odds		SMALLMONEY,
			betteam		VARCHAR(20),
			statusid	INT,
			livehomescore	INT,
			liveawayscore	INT,
			liveindicator	BIT,
			leagueid	INT,
			sporttype	INT,
			isNeutral	BIT,
			matchid		INT,
			matchcode	VARCHAR(50),
			matchdate	DATETIME,
			--for generating combination parlays
			RN TINYINT, -- set No. for selection in the combination
			CNT TINYINT, -- total selection count, base on bettransm/14
			bCNT TINYINT -- total selection count, stored in bettrans
		)
DECLARE @tmpResults TABLE (
		winlostdate DATETIME,
		transid		BIGINT,
		serial		BIGINT,
		statusid	INT,
		status		VARCHAR(20),	
		modds		SMALLMONEY,
		stake		MONEY,
		winlost		MONEY,
		comm  		MONEY,
		playercomm  MONEY
	)			
DECLARE @betParlayDetail TABLE (
		RefNo		bigint, 
		Serial		int, 				 				
		matchid		int				
	)
	DECLARE @tmpMatch AS TABLE(
			serial		BIGINT,
			homeid		INT,
			awayid		INT
		)	

	DECLARE @minMatchdate DATETIME,
			@maxMatchdate DATETIME

SELECT @currency = currency FROM custinfo c WITH (NOLOCK)
WHERE custid = @custid

INSERT INTO @parlay_base(transid,refno,winlostdate,bettype,homeid,awayid,hdp1,hdp2,odds,betteam,statusid,
						livehomescore,liveawayscore,liveindicator,leagueid,sporttype,isNeutral,matchid,matchcode,matchdate)

SELECT	bm.transid, bm.refno, bm.winlostdate,bm.bettype,m.homeid, m.awayid, bm.hdp1, bm.hdp2, bm.odds, bm.betteam,
		bm.statusid, bm.livehomescore, bm.liveawayscore, bm.liveindicator, m.leagueid, m.sporttype, m.isNeutral ,m.matchid,	m.matchcode, bm.matchdate
FROM bettransm bm WITH(NOLOCK)
	INNER JOIN match m WITH (NOLOCK) ON bm.matchid = m.matchid
WHERE refno = @refno AND custid = @custid

UNION

SELECT	bm.transid, bm.refno, bm.winlostdate,bm.bettype,m.homeid, m.awayid, bm.hdp1, bm.hdp2, bm.odds, bm.betteam,
		bm.statusid, bm.livehomescore, bm.liveawayscore, bm.liveindicator, m.leagueid, m.sporttype, m.isNeutral ,m.matchid,	m.matchcode, bm.matchdate
FROM bettransm14 bm WITH(NOLOCK)
	INNER JOIN match14 m WITH (NOLOCK) ON bm.matchid = m.matchid
WHERE refno = @refno

UNION 

SELECT	bm.transid, bm.refno, bm.winlostdate,bm.bettype,m.homeid, m.awayid, bm.hdp1, bm.hdp2, bm.odds, bm.betteam,
		bm.statusid, bm.livehomescore, bm.liveawayscore, bm.liveindicator, m.leagueid, m.sporttype, m.isNeutral ,m.matchid,	m.matchcode, bm.matchdate
FROM DBARC.bodb_archive.dbo.bettransm bm WITH(NOLOCK)
	INNER JOIN DBARC.bodb_archive.dbo.match_bk m WITH (NOLOCK) ON bm.matchid = m.matchid
WHERE refno = @refno


SELECT	@minMatchdate = MIN(matchdate),
		@maxMatchdate = MAX(matchdate)
FROM @parlay_base

	
IF @minMatchdate < @BalanceUpDay
BEGIN
	INSERT INTO @tmpBettrans (transid, transdate, refno, winlostdate, odds, stake, actual_stake, winlost, playercomm, status, betteam, ip, spositiontaking,
		mpositiontaking, apositiontaking, swinlost,	mwinlost, awinlost,	sdiscount, adiscount, discount, scomm, acomm, comm, N, cnt, bitmap)
	SELECT
		transid,
		transdate,
		refno,
		winlostdate,
		modds as odds,
		stake,
		actual_stake,
		CASE WHEN statusid NOT IN (0,1) THEN winlost - actual_stake ELSE winlost END as winlost,		
		playercomm,
		status,
		betteam,		
		ip,
		spositiontaking,
		mpositiontaking,
		apositiontaking,
		swinlost,
		mwinlost,
		awinlost,
		sdiscount,
		adiscount,
		discount,
		scomm ,
		acomm ,
		comm ,
		len(betteam) as N,
		hdp1 as cnt,
		hdp2 as bitmap
	FROM DBARC.bodb_archive.dbo.bettrans_bk b WITH(NOLOCK) 
	WHERE custid = @custid AND refno = @refno AND matchid = 29 AND bettype = 29
		AND transid NOT IN (SELECT transid FROM @tmpBettrans)
	
	INSERT INTO @tmpResults(winlostdate, serial, modds, stake, winlost, statusid, comm,playercomm)
			SELECT winlostdate, serial, modds, stake, winlost, statusid, comm, CASE WHEN statusid IN (112,113) THEN playercomm ELSE 0 END AS playercomm 
			FROM DBARC.bodb_archive.dbo.betparlayresult b WITH(NOLOCK) 
			WHERE refno = @refno
END
IF @minMatchdate <= @MoveBetsDay  --- get data from bettrans14
BEGIN	
	INSERT INTO @tmpBettrans (transid, transdate, refno, winlostdate, odds, stake, actual_stake, winlost, playercomm, status, betteam, ip, spositiontaking,
		mpositiontaking, apositiontaking, swinlost,	mwinlost, awinlost,	sdiscount, adiscount, discount, scomm, acomm, comm, N, cnt, bitmap)
	SELECT
		transid,
		transdate,
		refno,
		winlostdate,
		modds as odds,
		stake,
		actual_stake,
		CASE WHEN statusid NOT IN (0,1) THEN winlost - actual_stake ELSE winlost END as winlost,		
		playercomm,
		status,
		betteam,		
		ip,
		spositiontaking,
		mpositiontaking,
		apositiontaking,
		swinlost,
		mwinlost,
		awinlost,
		sdiscount,
		adiscount,
		discount,
		scomm,
		acomm,
		comm,
		len(betteam) as N,
		hdp1 as cnt,
		hdp2 as bitmap
	FROM bettrans14 b WITH(NOLOCK) 
	WHERE custid = @custid AND refno = @refno AND matchid = 29 AND bettype = 29
		AND transid NOT IN (SELECT transid FROM @tmpBettrans)
END			
IF @maxMatchdate > @MoveBetsDay  --- get data from bettrans
BEGIN		
	INSERT INTO @tmpBettrans (transid, transdate, refno, winlostdate, odds, stake, actual_stake, winlost, playercomm, status, betteam, ip, spositiontaking,
		mpositiontaking, apositiontaking, swinlost,	mwinlost, awinlost,	sdiscount, adiscount, discount, scomm, acomm, comm,N, cnt, bitmap)
	SELECT
		transid,
		transdate,
		refno,
		winlostdate,
		modds as odds,
		stake,
		actual_stake,
		winlost - actual_stake as winlost,		
		playercomm,
		status,
		betteam,		
		ip,
		spositiontaking,
		mpositiontaking,
		apositiontaking,
		swinlost,
		mwinlost,
		awinlost,
		sdiscount,
		adiscount,
		discount,
		scomm,
		acomm,
		comm,
		len(betteam) as N,
		hdp1 as cnt,
		hdp2 as bitmap
	FROM bettrans b WITH(NOLOCK) 
	WHERE custid = @custid AND refno = @refno AND matchid = 29 AND bettype = 29
		AND transid NOT IN (SELECT transid FROM @tmpBettrans)
END
	
		
INSERT INTO @tmpResults(winlostdate, serial, modds, stake, winlost, statusid, comm,playercomm)
				SELECT winlostdate, serial, modds, stake, winlost, statusid, comm,CASE WHEN statusid IN (112,113) THEN playercomm ELSE 0 END AS playercomm 
				FROM betparlayresult b WITH(NOLOCK) 
				WHERE refno = @refno AND serial NOT IN (SELECT serial FROM @tmpResults)

----- generate betparlay detail
IF @minMatchdate < @BalanceUpday
BEGIN
	;WITH sub AS 
	(
		SELECT ROW_NUMBER() OVER (ORDER BY matchid) RN, matchid FROM @parlay_base
	)
	UPDATE pb
	SET RN = sub.RN
	FROM sub
		INNER JOIN @parlay_base pb ON sub.matchid = pb.matchid

	-- prepare N
	;WITH sub AS (SELECT count(*) cnt FROM @parlay_base)
	UPDATE pb
	SET CNT = sub.cnt, bCNT = t.N
	FROM sub , @parlay_base pb , @tmpBettrans t
	
	IF NOT EXISTS(SELECT 1 FROM @parlay_base WHERE cnt <> bCnt)
	BEGIN
		INSERT INTO @betParlayDetail
			(RefNo, Serial, matchid )
			SELECT 
				pb.RefNo, rc.Serial, matchid
			FROM
				@parlay_base pb
				INNER JOIN @tmpBettrans tb ON pb.refno = tb.refno
				INNER JOIN dbo.RefCombination rc ON pb.RN = rc.seq AND pb.CNT = rc.N AND (tb.bitmap&rc.bitmap) > 0
	END	
END
ELSE
BEGIN
	INSERT INTO @betParlayDetail(RefNo, Serial, matchid )
			SELECT refno, serial, matchid
			FROM betParlayDetail WITH(NOLOCK)
			WHERE refno = @refno
END
----- get homeid, awayid
IF @MinMatchdate < @BalanceUpday
BEGIN
	INSERT INTO @tmpMatch
	SELECT
		p.serial,
		homeid,
		awayid
	FROM @tmpResults p 
		INNER JOIN @betParlayDetail b ON p.Serial = b.Serial
		INNER JOIN DBARC.BODB_Archive.dbo.match_bk m WITH(NOLOCK) ON b.matchid = m.matchid	
	WHERE p.statusid <> 113
END
IF @MinMatchdate <= @MoveBetsDay
BEGIN
	INSERT INTO @tmpMatch
	SELECT
		p.serial,
		homeid,
		awayid
	FROM @tmpResults p 
		INNER JOIN @betParlayDetail b ON p.Serial = b.Serial
		INNER JOIN match14 m WITH(NOLOCK) ON b.matchid = m.matchid	
	WHERE p.statusid <> 113
END
IF @MaxMatchdate > @MoveBetsDay
BEGIN
	INSERT INTO @tmpMatch
	SELECT
		p.serial,
		homeid,
		awayid
	FROM @tmpResults p 
		INNER JOIN @betParlayDetail b ON p.Serial = b.Serial
		INNER JOIN match m WITH(NOLOCK) ON b.matchid = m.matchid	
	WHERE p.statusid <> 113
END			
			
			
---- calculate outstanding
SELECT @Outstanding = MAX(stake)
FROM @tmpBettrans

SELECT @Outstanding = @Outstanding - ISNULL(SUM(stake),0)
FROM @tmpResults
WHERE statusID NOT IN (0,1)
			
SELECT @USD=e.USD,@EUR = e.EUR, @MYR = e.MYR FROM (SELECT * FROM Lrf_f_GetExchangeDaily(@Today,@Today))e 
WHERE e.ExchangeDate = @Today
AND e.ExchangeId = @currency

SELECT @Outstanding = ISNULL(@Outstanding, 0)
SELECT @OutstandingUSD = ISNULL(@Outstanding, 0)	 * @USD 
SELECT @OutstandingEUR = ISNULL(@Outstanding, 0)	 * @EUR					
SELECT @OutstandingMYR = ISNULL(@Outstanding, 0)	 * @MYR
			
			
SELECT @Fromdate=MIN(winlostdate),@Todate=MAX(winlostdate) FROM @tmpResults			
			
-- return combo detail
SELECT 
	0 as [order],
	winlostdate,
	0 transid,
	serial,
	statusid,	
	CASE statusid WHEN 101 THEN 'REJECT'
					WHEN 102 THEN 'VOID'
					WHEN 103 THEN 'REFUND'
					WHEN 111 THEN 'DRAW'
					WHEN 112 THEN 'WON' ELSE '' END AS status,
	modds,
	stake,
	CAST (stake * e.usd AS money) as stakeusd,
	CAST (stake * e.eur AS money) as stakeeur,
	CAST (stake * e.myr AS money) as stakemyr,
	winlost - stake AS winlost,
	cast ((winlost - stake) * e.usd AS money) as winlostusd,
	cast ((winlost - stake) * e.eur AS money) as winlosteur,
	cast ((winlost - stake) * e.myr AS money) as winlostmyr,
	comm,
	cast (comm * e.usd as money) as commusd,
	cast (comm * e.eur as money) as commeur,
	cast (comm * e.myr as money) as commmyr,
	playercomm,
	cast(playercomm*e.usd as money) as playercommusd,
	cast(playercomm*e.eur as money) as playercommeur,
	cast(playercomm*e.myr as money) as playercommmyr
	
FROM @tmpResults b
INNER JOIN (SELECT * FROM Lrf_f_GetExchangeDaily(@FromDate,@ToDate))e 
ON e.ExchangeDate = b.winlostdate   AND e.exchangeid = @currency
WHERE statusid NOT IN (0,1,113)

UNION ALL

SELECT 
	999 as [order],
	winlostdate,	
	0 AS transid,	
	0 AS serial,
	113 AS statusid,	
	'LOSE' AS status,
	0 AS modds,	
	SUM(stake) AS stake,	
	CAST(sum(stake * e.usd) AS money) as stakeusd,
	cast(sum(stake * e.eur) as money) as stakeeur,
	cast(sum(stake * e.myr) as money) as stakemyr,
	SUM(winlost - stake) AS winlost,
	cast(SUM((winlost - stake)* e.usd) as money) AS winlostusd,
	cast(SUM((winlost - stake)* e.eur) as money) AS winlosteur,
	cast(SUM((winlost - stake)* e.myr) as money) AS winlostmyr,
	sum(comm) as comm,
	cast(sum(comm*e.usd) as money) as commusd,
	cast(sum(comm*e.eur) as money) as commeur,
	cast(sum(comm*e.myr) as money) as commmyr,
	sum(playercomm) as playercomm,
	cast(sum(playercomm*e.usd) as money) as playercommusd,
	cast(sum(playercomm*e.eur) as money) as playercommeur,
	cast(sum(playercomm*e.myr) as money) as playercommmyr
	
FROM @tmpResults b
INNER JOIN (SELECT * FROM Lrf_f_GetExchangeDaily(@FromDate,@ToDate))e 
ON e.ExchangeDate = b.winlostdate   AND e.exchangeid = @currency
WHERE statusid = 113
GROUP BY 
	winlostdate 
ORDER BY [order] asc,winlostdate ASC 

SELECT * FROM @tmpMatch

GO 
 GRANT VIEW DEFINITION ON [dbo].[OAS_BetList_SelCombinationParlayDetail] TO [vnteam]
GO 
 GRANT EXECUTE ON [dbo].[OAS_BetList_SelCombinationParlayDetail] TO [bodbLicenseeNet]
GO 
 GRANT EXECUTE ON [dbo].[OAS_BetList_SelCombinationParlayDetail] TO [bodbAdminNet]
GO 
