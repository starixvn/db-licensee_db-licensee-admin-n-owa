USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[OAS_Report_GetTotalTicket_NewStruct]    Script Date: 07/10/2014 00:32:17 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.OAS_Report_GetTotalTicket_NewStruct    Script Date: 4/18/2014 17:59:02  ******/

ALTER PROCEDURE [dbo].[OAS_Report_GetTotalTicket_NewStruct]   
	@NormalLicensee VARCHAR(1000),  
	@Operator  VARCHAR(1000),  
	@FromDate  SMALLDATETIME,    
	@ToDate   SMALLDATETIME,    
	@SportID  INT = 0,
	@GroupBy  TINYINT = 2
AS  
  
/*  
 * Created by : 20131203@Francis 
 * Task  : Get Total Transactions report for Sportbook (compatible with the new structure)
 * DB   : DB052.bodb02
 * Revisions :  
 	
 * Param's Explanation:    
 *  - @NormalLicensee : List of normal licensee ID separated by ','  
 *  - @Operator   : List of operator ID separated by ','  
 *  - @GroupBy: + Value = 1: Daily grouping type
			    + Value = 2: Monthly grouping type
 */  
 
BEGIN
	declare @sql varchar(8000)
	SELECT @sql = 'SET NOCOUNT ON  ' + char(13)

	SELECT @Fromdate=ltrim(rtrim(@Fromdate)),@Todate=ltrim(rtrim(@Todate))

	--declare
	DECLARE @tmpLicenseeReseller AS TABLE (FromPartyID INT, ToPartyID INT, FromDate DateTime, OldRefID INT)
	DECLARE @data as table (Winlostdate smalldatetime, FromPartyID int, ToPartyID int, BetCount int)
	DECLARE @tmpTotalBet AS TABLE (GroupBy varchar(8), ResellerID int, ResellerName varchar(50), LicenseeName varchar(50), BetCount int)
		
	
	DECLARE @tmpTable AS TABLE (PartyID INT)
	INSERT INTO @tmpTable (PartyID)
	SELECT PartyID FROM bodb_licensee.dbo.OAS_Party (NOLOCK)
		   WHERE PartyName IN ('Starlit','BA(FDL)')
	
	--enhance performance
	create table #tmpBetting (rptDate datetime,siteID INT,betcount INT)
	create table #tmpBetting_BA (rptDate datetime,siteID INT,betcount INT)
	
	if @SportID <> 0
	BEGIN
		INSERT INTO #tmpBetting(rptDate,siteID,betcount)
		SELECT b.rptDate, b.SiteID, SUM(b.betcount)
		FROM bodb_licensee.dbo.rpt_betting b WITH (NOLOCK)
		LEFT JOIN bodb02.dbo.League l WITH (NOLOCK) ON b.leagueid = l.leagueid
		where b.rptDate between @FromDate AND @ToDate
		AND b.status NOT IN (-1,103)
		AND b.CurrencyID<>20
		AND ISNULL(b.CustomerCategory,0) not in (27,28)
		AND (b.bettype<31 OR b.bettype BETWEEN 121 AND 999)
		AND b.bettype NOT IN (9,29) AND l.Sporttype = convert(varchar(10), @SportID)
		GROUP BY b.rptDate, b.SiteID
		
		INSERT INTO #tmpBetting_BA(rptDate,siteID,betcount)
		SELECT b.rptDate, b.SiteID, SUM(b.betcount)
		FROM bodb_licensee.dbo.rpt_betting_BA b WITH (NOLOCK)
		LEFT JOIN bodb02.dbo.League l WITH (NOLOCK) ON b.leagueid = l.leagueid
		where b.rptDate between @FromDate AND @ToDate
		AND b.status NOT IN (-1,103)
		AND b.CurrencyID<>20
		AND b.bettype NOT IN (9,29) AND l.Sporttype = convert(varchar(10), @SportID)
		GROUP BY b.rptDate, b.SiteID
	end
	else
	begin
		INSERT INTO #tmpBetting(rptDate,siteID,betcount)
		SELECT b.rptDate, b.SiteID, SUM(b.betcount)
		FROM bodb_licensee.dbo.rpt_betting b WITH (NOLOCK)
		LEFT JOIN bodb02.dbo.League l WITH (NOLOCK) ON b.leagueid = l.leagueid
		where b.rptDate between @FromDate AND @ToDate
		AND b.status NOT IN (-1,103)
		AND b.CurrencyID<>20
		AND ISNULL(b.CustomerCategory,0) not in (27,28)
		AND (b.bettype<31 OR b.bettype BETWEEN 121 AND 999)
		GROUP BY b.rptDate, b.SiteID
		
		INSERT INTO #tmpBetting_BA(rptDate,siteID,betcount)
		SELECT b.rptDate, b.SiteID, SUM(b.betcount)
		FROM bodb_licensee.dbo.rpt_betting_BA b WITH (NOLOCK)
		LEFT JOIN bodb02.dbo.League l WITH (NOLOCK) ON b.leagueid = l.leagueid
		where b.rptDate between @FromDate AND @ToDate
		AND b.status NOT IN (-1,103)
		AND b.CurrencyID<>20
		GROUP BY b.rptDate, b.SiteID
	end
	--end enhancement
	
	IF LTRIM(RTRIM(ISNULL(@NormalLicensee,''))) <> ''
	BEGIN	
	insert into @tmpLicenseeReseller (FromPartyID, ToPartyID, FromDate, OldRefID)
	select DISTINCT ci.FromParty, ci.ToParty, case WHEN @FromDate <= ci.FromDate THEN ci.FromDate ELSE @FromDate END, p.OldRefID
	from bodb_licensee.dbo.OAS_ChargeInfo ci (NOLOCK) inner JOIN bodb_Licensee.dbo.OAS_Party p (NOLOCK)
	ON ci.FromParty = p.PartyID
	where (@FromDate BETWEEN ci.FromDate AND ci.ToDate OR 
		  @ToDate BETWEEN ci.FromDate AND ci.ToDate)
		  AND ci.ChargeType = 2
		  AND ci.ProductID = 0
		  --just get Licensees from Oneworks,BCH and LDL
		  and ci.ToParty IN (SELECT PartyID FROM bodb_Licensee.dbo.OAS_Party (NOLOCK) WHERE PartyName IN ('Oneworks','BCH','LDL'))
		  --strSplit is a user-defined function
		  and ci.FromParty IN (SELECT RTRIM(LTRIM(VAL)) FROM strSplit(@NormalLicensee,',')) 
	end 
		  
	IF LTRIM(RTRIM(ISNULL(@Operator,''))) <> ''
	BEGIN
	insert into @tmpLicenseeReseller (FromPartyID, ToPartyID, FromDate, OldRefID)
	select DISTINCT ci.FromParty, ci.ToParty, case WHEN @FromDate <= ci.FromDate THEN ci.FromDate ELSE @FromDate END, p.OldRefID
	from bodb_licensee.dbo.OAS_ChargeInfo ci (NOLOCK) inner JOIN bodb_Licensee.dbo.OAS_Party p (NOLOCK)
	ON ci.FromParty = p.PartyID
	where (@FromDate BETWEEN ci.FromDate AND ci.ToDate OR 
		  @ToDate BETWEEN ci.FromDate AND ci.ToDate)
		  AND ci.ChargeType = 2
		  AND ci.ProductID = 0
		  and ci.ToParty IN (SELECT RTRIM(LTRIM(VAL)) FROM strSplit(@Operator,','))
	END
	--1. Exclude Licensees from Starlit and BA(FDL)
	--For Deposit Licensees 
	IF exists (SELECT 1 FROM @tmpLicenseeReseller tlr 
						WHERE tlr.ToPartyID NOT IN (SELECT PartyID FROM @tmpTable))
	BEGIN
		IF exists (SELECT 1 FROM @tmpLicenseeReseller tlr
							INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd1 (NOLOCK)
							ON tlr.FromPartyID = pd1.PartyID
							WHERE pd1.IsDeposit = 1)
		BEGIN
			insert into @data (Winlostdate, FromPartyID, ToPartyID, BetCount)
			select b.rptDate, lr.FromPartyID, lr.ToPartyID, SUM(betcount) AS BetCount
			from #tmpBetting b (NOLOCK) inner JOIN @tmpLicenseeReseller lr
			ON b.siteID = lr.OldRefID inner JOIN bodb_licensee.dbo.OAS_PartyDetail pd (NOLOCK) 
			ON lr.FromPartyID = pd.PartyID
	 		where pd.IsDeposit = 1 
	 		AND b.rptDate BETWEEN lr.FromDate AND @ToDate
	 		--Exclude Licensees from Starlit, BA(FDL)
	 		and lr.ToPartyID NOT IN (SELECT PartyID FROM @tmpTable)
	 		group BY b.rptDate, lr.FromPartyID, lr.ToPartyID
		END 
	
	--For Credit Licensees
		IF exists (SELECT 1 FROM @tmpLicenseeReseller tlr
							INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd1 (NOLOCK)
							ON tlr.FromPartyID = pd1.PartyID
							WHERE pd1.IsDeposit = 0)
		BEGIN
			insert into @data (Winlostdate, FromPartyID, ToPartyID, BetCount)
			select b.rptDate, lr.FromPartyID, lr.ToPartyID, SUM(betcount) AS BetCount
			from @tmpLicenseeReseller lr inner JOIN bodb_licensee.dbo.OAS_PartyDetail pd (NOLOCK) 
			ON lr.FromPartyID = pd.PartyID inner join bodb_Licensee.dbo.labels lb (NOLOCK) 
			ON lr.OldRefID = lb.LicenseeID inner JOIN #tmpBetting b (NOLOCK)
			ON b.siteID = lb.LabelID
	 		where pd.IsDeposit = 0 
	 		AND b.rptDate BETWEEN lr.FromDate AND @ToDate
	 		--Exclude Licensees from Starlit, BA(FDL)
	 		and lr.ToPartyID NOT IN (SELECT PartyID FROM @tmpTable)
	 		group BY b.rptDate, lr.FromPartyID, lr.ToPartyID
		END 
	END
	
	--2. For Licensees from Starlit and BA(FDL)
	IF exists (SELECT 1 FROM @tmpLicenseeReseller 
			   WHERE ToPartyID IN (SELECT PartyID FROM @tmpTable))
	BEGIN
		insert into @data (Winlostdate, FromPartyID, ToPartyID, BetCount)
		select b.rptDate, lr.FromPartyID, lr.ToPartyID, SUM(betcount) AS BetCount
		from #tmpBetting_BA b (NOLOCK) inner JOIN @tmpLicenseeReseller lr
		ON b.siteID = lr.OldRefID inner JOIN bodb_licensee.dbo.OAS_PartyDetail pd (NOLOCK) 
		ON lr.FromPartyID = pd.PartyID
	 	where pd.IsDeposit = 1 
	 	AND b.rptDate BETWEEN lr.FromDate AND @ToDate
	 	--Licensees from Starlit, BA(FDL)
	 	and lr.ToPartyID IN (SELECT PartyID FROM @tmpTable)
	 	group BY b.rptDate, lr.FromPartyID, lr.ToPartyID
	END 
		
	if (@GroupBy = 1)		
	begin
	
		insert INTO @tmpTotalBet (GroupBy, ResellerID, ResellerName, LicenseeName, BetCount)
		select CONVERT(VARCHAR(8),d.Winlostdate,112) AS GroupBy,
			d.ToPartyID AS ResellerID, 
			p.PartyName AS ResellerName,
			CASE WHEN (r.ResellerType = 1 OR p.PartyName = 'BA(FDL)') THEN p1.PartyName ELSE '' END as LicenseeName,
			ISNULL(SUM(d.BetCount),0) as BetCount
		from
			@data d inner JOIN bodb_licensee.dbo.OAS_Party p (NOLOCK)
			ON d.ToPartyID = p.PartyID inner JOIN bodb_licensee.dbo.OAS_Party p1 (NOLOCK)
			ON d.FromPartyID = p1.PartyID inner JOIN bodb_licensee.dbo.Resellers r (NOLOCK)
			ON r.ResellerID = p.OldRefID
		group by
			CONVERT(VARCHAR(8),d.winlostdate,112),
			d.ToPartyID, p.PartyName,
		    CASE WHEN (r.ResellerType = 1 OR p.PartyName = 'BA(FDL)') THEN p1.PartyName ELSE '' END
		order by
		    CONVERT(VARCHAR(8),d.winlostdate,112), p.PartyName,
		    CASE WHEN (r.ResellerType = 1 OR p.PartyName = 'BA(FDL)') THEN p1.PartyName ELSE '' END
	end
	else
	begin
		insert INTO @tmpTotalBet (GroupBy, ResellerID, ResellerName, LicenseeName, BetCount)
		select CONVERT(VARCHAR(6),d.Winlostdate,112) AS GroupBy,
			d.ToPartyID AS ResellerID, 
			p.PartyName AS ResellerName,
			CASE WHEN (r.ResellerType = 1 OR p.PartyName = 'BA(FDL)') THEN p1.PartyName ELSE '' END as LicenseeName,
			ISNULL(SUM(d.BetCount),0) as BetCount
		from
			@data d inner JOIN bodb_licensee.dbo.OAS_Party p (NOLOCK)
			ON d.ToPartyID = p.PartyID inner JOIN bodb_licensee.dbo.OAS_Party p1 (NOLOCK)
			ON d.FromPartyID = p1.PartyID inner JOIN bodb_licensee.dbo.Resellers r (NOLOCK)
			ON r.ResellerID = p.OldRefID
		group by
			CONVERT(VARCHAR(6),d.winlostdate,112),
			d.ToPartyID, p.PartyName,
		    CASE WHEN (r.ResellerType = 1 OR p.PartyName = 'BA(FDL)') THEN p1.PartyName ELSE '' END
		order by
		   CONVERT(VARCHAR(6),d.winlostdate,112), p.PartyName,
		   CASE WHEN (r.ResellerType = 1 OR p.PartyName = 'BA(FDL)') THEN p1.PartyName ELSE '' END
	end
	
	--Add Total Cost
	SELECT tb.GroupBy, tb.ResellerID, tb.ResellerName, tb.LicenseeName, tb.BetCount, tb.BetCount * ci.Rate AS TotalCost
	FROM @tmpTotalBet tb INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci
		 ON tb.ResellerID = ci.FromParty 
		 AND tb.BetCount BETWEEN ci.MinTrans AND ci.MaxTrans
	WHERE @FromDate BETWEEN ci.FromDate AND ci.ToDate
		
	DROP TABLE #tmpBetting
	DROP TABLE #tmpBetting_BA
	
END  
GO
GRANT EXECUTE ON [dbo].[OAS_Report_GetTotalTicket_NewStruct] TO [bodbLicenseeNet] 
GRANT EXECUTE ON [dbo].[OAS_Report_GetTotalTicket_NewStruct] TO bodbAdminNet 
GRANT VIEW DEFINITION ON [dbo].[OAS_Report_GetTotalTicket_NewStruct] TO [vnteam] 


