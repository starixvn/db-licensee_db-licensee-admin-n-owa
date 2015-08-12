ALTER PROCEDURE [dbo].[OAS_BetList_SelParlayDetail]
	@TransID	bigint,
	@Langkey	VARCHAR(10) = 'en-US'
 AS
/*
Created: Francis@20140120
Task : get parlay tickets (cloned from Lrf_BetList_SelParlayDetail to use for OWA)
DB: DB052.bodb02
Original: [Lrf_BetList_SelParlayDetail]

Revisions:    
	
*/
SET NOCOUNT ON
DECLARE	@tmpParlay	TABLE(
	transid		BIGINT,
	sporttype	INT,
	leagueid	INT,
	bettype		INT,
	homeid		INT,
	awayid		INT,
	hdp1		FLOAT,
	hdp2		FLOAT,
	odds		SMALLMONEY,
	betteam		NVARCHAR(50),
	livehomescore	SMALLINT,
	liveawayscore	SMALLINT,
	liveindicator	BIT,
	betstatus	NVARCHAR(50),
	isNeutral	BIT,
	statusID INT
)	

DECLARE @refno bigint, @custID INT

SELECT @refno = refno, @custID = custid from bettrans with (NOLOCK) WHERE TransID = @TransID
IF @refno IS NULL 	
BEGIN
	SELECT @refno = refno, @custID = custid from bettrans14 with (NOLOCK) WHERE TransID = @TransID
	IF @refno IS NULL 
	BEGIN
		SELECT @refno = refno, @custID = custid from DBARC.bodb_archive.dbo.bettrans_BK with (NOLOCK) WHERE TransID = @TransID
	END
END
IF EXISTS (SELECT 1 FROM bettransm WITH (NOLOCK) WHERE refno = @refno AND custid = @custid)
BEGIN
	INSERT INTO @tmpParlay (
		transid,
		sporttype,
		leagueid,
		bettype,
		homeid,
		awayid,
		hdp1,
		hdp2,
		odds,
		betteam,
		livehomescore,
		liveawayscore,
		liveindicator,
		betstatus,
		isNeutral,
		statusID
	)
	SELECT
		b.transid,
		m.Sporttype,
		m.LeagueID,		
		b.Bettype ,
		m.homeID,
		m.awayID,
		convert(float, b.hdp1) as Hdp1, 
		convert(float, b.hdp2) as Hdp2, 
		b.odds,
		b.betteam,
		b.livehomescore,
		b.liveawayscore,
		b.liveindicator,
		m.betstatus,
		m.isNeutral,
		b.statusID
	FROM(	SELECT 
					transid,
					matchid,  
					Bettype, 
					hdp1, 
					hdp2, 
					odds, 
					betteam, 
					livehomescore,
					liveawayscore,
					liveindicator,
					statusID
			FROM	BettransM with (nolock)
					WHERE refno=@refno AND custID = @custID              
		) AS b		
			inner join match as m with (nolock) on b.matchid=m.matchid
END
IF EXISTS (SELECT 1 FROM bettransm14 WITH (NOLOCK) WHERE refno = @refno AND custid = @custid)
BEGIN
	INSERT INTO @tmpParlay (
		transid,
		sporttype,
		leagueid,
		bettype,
		homeid,
		awayid,
		hdp1,
		hdp2,
		odds,
		betteam,
		livehomescore,
		liveawayscore,
		liveindicator,
		betstatus,
		isNeutral,
		statusID
	)
	SELECT
		b.transid,
		m.Sporttype,
		m.LeagueID,		
		b.Bettype ,
		m.homeID,
		m.awayID,
		convert(float, b.hdp1) as Hdp1, 
		convert(float, b.hdp2) as Hdp2, 
		b.odds,
		b.betteam,
		b.livehomescore,
		b.liveawayscore,
		b.liveindicator,
		m.betstatus,
		m.isNeutral,
		b.statusID
	FROM(	SELECT 
					transid,
					matchid,  
					Bettype, 
					hdp1, 
					hdp2, 
					odds, 
					betteam, 
					livehomescore,
					liveawayscore,
					liveindicator,
					statusID
			FROM	BettransM14 with (nolock)
					WHERE refno=@refno AND custID = @custID              
		) AS b		
			inner join match14 as m with (nolock) on b.matchid=m.matchid
END
IF EXISTS (SELECT 1 FROM DBARC.bodb_archive.dbo.BettransM WITH (NOLOCK) WHERE refno = @refno)
BEGIN
	INSERT INTO @tmpParlay (
		transid,
		sporttype,
		leagueid,
		bettype,
		homeid,
		awayid,
		hdp1,
		hdp2,
		odds,
		betteam,
		livehomescore,
		liveawayscore,
		liveindicator,
		betstatus,
		isNeutral,
		statusID
	)
	SELECT
		b.transid,
		m.Sporttype,
		m.LeagueID,		
		b.Bettype ,
		m.homeID,
		m.awayID,
		convert(float, b.hdp1) as Hdp1, 
		convert(float, b.hdp2) as Hdp2, 
		b.odds,
		b.betteam,
		b.livehomescore,
		b.liveawayscore,
		b.liveindicator,
		m.betstatus,
		m.isNeutral,
		b.statusID
	FROM(	SELECT 
					transid,
					matchid,  
					Bettype, 
					hdp1, 
					hdp2, 
					odds, 
					betteam, 
					livehomescore,
					liveawayscore,
					liveindicator,
					statusID
			FROM	DBARC.bodb_archive.dbo.BettransM with (nolock)
					WHERE refno=@refno  AND custID = @custID          
		) AS b		
			inner join DBARC.bodb_archive.dbo.match_bk as m with (nolock) on b.matchid=m.matchid	
END
SELECT * FROM @tmpParlay
ORDER BY transID DESC 


GO 
 GRANT VIEW DEFINITION ON [dbo].[OAS_BetList_SelParlayDetail] TO [vnteam]
GO 
 GRANT EXECUTE ON [dbo].[OAS_BetList_SelParlayDetail] TO [bodbLicenseeNet]
GO 
 GRANT EXECUTE ON [dbo].[OAS_BetList_SelParlayDetail] TO [bodbAdminNet]
GO 
