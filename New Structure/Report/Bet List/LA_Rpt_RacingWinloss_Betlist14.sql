USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_RacingWinloss_Betlist14]    Script Date: 08/10/2014 11:25:41 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[LA_Rpt_RacingWinloss_Betlist14]
    @leagueid		INT,
    @raceNo		VARCHAR(10), 
    @currency		INT,
    @winlostdate	DATETIME,
    @PartyID 		INT,
    @Excludetest	BIT			= 0
AS
/*
    Created by: 20140923@Florent    
    Task: Racing Detailed Bet List
    DB: DBEXT.BODB02

    Revisions:

    Param's Explanation:
*/

BEGIN
    SET NOCOUNT ON
    
    --from party to licensee
	DECLARE @licenseeID INT 
	DECLARE @tempAg	TABLE( custID INT PRIMARY KEY, Currency INT)  
	
     SELECT @licenseeID = OldRefID 
	FROM bodb_licensee.dbo.OAS_Party WITH (NOLOCK) 
	WHERE PartyID = @PartyID AND PartyType = 1

	INSERT INTO @tempAg (custID,currency) 
	SELECT custID,currency 
	   FROM bodb_Licensee.dbo.LicenseeCust lc(NOLOCK) 
	   WHERE (@excludeTest=0 OR (@excludeTest=1 AND Currency <> 20))	
			 AND lc.LicenseeID = @licenseeID

    DECLARE @CommSetting TABLE
    (    MatchID int,    
        teamid int,
        matchcode varchar(100),    
        IBCCommIncomeAddToteFee INT, -- IBC Comm Income add Tote Fee or not 
                                         -- [0]: Not include Tote Fee; [1]: Plus Tote Fee; [-1]: Minus Tote Fee 
        ToteCommWin smallmoney,
        ToteCommPlace smallmoney,
        ToteCommWP smallmoney,
        ToteFee smallmoney    
    )
    
    INSERT INTO @CommSetting (
            MatchID,teamid,matchcode,IBCCommIncomeAddToteFee,ToteCommWin, ToteCommPlace, ToteCommWP, ToteFee
    )
    SELECT    o.orid as matchid, o.teamid, o.matchcode,
                CASE WHEN m.partnerID IN (2,3,4) THEN 0 ELSE -1 END,
                p.ToteCommWin, p.ToteCommPlace, (p.ToteCommWin + p.ToteCommPlace)/2 ToteCommWP, p.ToteFee 
    FROM    outright14 o WITH (NOLOCK)
            INNER JOIN RacingMeeting m WITH (NOLOCK) ON m.meetingID = o.leagueid 
            INNER JOIN LeagueDetail p WITH (NOLOCK) ON m.MeetingID = p.leagueID and p.programDate = o.programDate     
    WHERE    o.eventdate = @winlostdate 
            AND o.leagueid = @leagueid 
            AND o.groupmatch = @raceNo    
        
    SELECT    b.username,
            SUBSTRING(c.username2,  CHARINDEX('$',c.username2)+1, len(c.username2)-CHARINDEX('$',c.username2)) AS username2,
            b.transid,
            b.transdate,
            b.bettype,
            b.hdp1 winOdds,
            b.hdp2 placeOdds,
            b.odds,            
            b.stake,
            (b.winlost - b.actual_stake) winlost,
            (b.awinlost + b.mwinlost + b.swinlost) AS WLPTLicensee,
            (b.winlost - b.actual_stake)*(-ISNULL(b.oddsspread,0)) as WLPTIBC,
            CASE WHEN b.bettype = 31 THEN b.actual_stake*(1 - b.tpositiontaking - ISNULL(b.oddsspread,0))*(cs.ToteCommWin + cs.IBCCommIncomeAddToteFee*cs.ToteFee) - b.scomm
                WHEN b.bettype = 32 THEN b.actual_stake*(1 - b.tpositiontaking - ISNULL(b.oddsspread,0)) * (cs.ToteCommPlace + cs.IBCCommIncomeAddToteFee*cs.ToteFee)- b.scomm
                WHEN b.bettype = 33 THEN bm.TOPartner*((cs.ToteCommWin + cs.ToteCommPlace)/2 + cs.IBCCommIncomeAddToteFee*cs.ToteFee) - b.scomm END as CommIncomeIBC, 
            b.playercomm,
            CASE WHEN b.bettype = 33 AND b.liveawayscore = 0 THEN b.winlost - b.actual_stake/2 ELSE b.winlost END dividend,
            (b.comm - b.playercomm) AS commIncomeLicensee,
            CASE b.livehomescore WHEN 2 THEN 'WON' WHEN 4 THEN 'LOSE' ELSE '' END winStatus,
            CASE b.liveawayscore WHEN 2 THEN 'WON' WHEN 4 THEN 'LOSE' ELSE 'Refund' END placeStatus,
            b.status,
            cs.teamid, 
            cs.matchcode,
            b.virtualrate,
            --isnumeric(o.programID) isShowOTExRate
            CASE WHEN b.currency2 IS NULL THEN CONVERT(BIT,0) ELSE CONVERT(BIT,1) END AS isShowOTExRate
    FROM    bettrans14 b (NOLOCK)
		  INNER JOIN @tempAg t ON b.recommend = t.custID
            INNER JOIN @CommSetting cs ON b.matchid = cs.matchid
            LEFT JOIN (
                    SELECT refno,                        
                        SUM(CASE WHEN bettype = 32 AND liveawayscore = 0 THEN 0 ELSE stake*(1 -tpositiontaking - isnull(oddsspread,0))END) TOPartner                                
                    FROM bettransm14 WITH(NOLOCK)
                    GROUP BY refno
                ) bm ON b.transid = bm.refno
            INNER JOIN customer c (NOLOCK) ON b.custid = c.custid
    WHERE    b.ruben = 1 
            AND b.bettype in (31,32,33) 
            --AND b.status NOT in ('VOID','REJECT','DONE','REFUND')
            AND b.statusID NOT IN (101,102,103,121)
            AND b.currency = @currency 
            AND b.winlostdate = @winlostdate            
    ORDER BY b.username
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_RacingWinloss_Betlist14] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_RacingWinloss_Betlist14] TO bodbAdminNet 