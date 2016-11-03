USE [bodb_licensee]
GO
ALTER PROCEDURE [dbo].[KPI_GetTopThreeSports]   
	@ReportDate datetime = NULL,
	@BranchID int,
	@GroupID int
AS  
  
/*  
 * Created by : 20140117@Francis 
 * Task  : Get all data for sportbook TOP 3 Sports KPI report(exclude SUNCITY) 
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
   -20160726@Francis: Move SP to bodb_LicenseeReport - [Redmine: #60449]
 * Param's Explanation:    
 * 
 */  
 
BEGIN
	declare @SiteID int
	select @SiteID = SiteID FROM KPI_Groups (NOLOCK) where GroupID = @GroupID
	declare @SectionID int
	select @SectionID = SectionID FROM KPI_Sections (NOLOCK) where SectionName = 'Betting Statistics'
	declare @TempID int, @TempType int
	select @TempID = BranchID FROM KPI_Branches (NOLOCK) where BranchName = 'BA'
	select @TempType = GroupType FROM KPI_Groups (NOLOCK) WHERE GroupID = @GroupID
	CREATE TABLE #MTD_TopThreeSports
	(
		rptDate datetime
		,CurrencyID int
		,SportID int
		,Turnover float
	)
	
	CREATE CLUSTERED INDEX IX_MTD_TopThreeSports ON #MTD_TopThreeSports 
	(
		[rptDate] ASC,
		CurrencyID,
		SportID ASC
	)
	CREATE TABLE #TopThreeSportsResult 
	(
		SportRank int,
		SportName varchar(50),
		TurnOverPercentage float
	)

	
	DECLARE @Labels TABLE(LabelID int, DateStarted datetime)
	
	DECLARE 
    @Date_TheDayBefore datetime
    ,@Date_MTDCurrentMonth datetime
    ,@Date_MTDLastMonth datetime
    ,@Date_FirstDayOfYear datetime
    ,@Date_FirstDayOfLastMonth datetime
    ,@Date_FirstDayOfCurrentMonth datetime
    ,@FromDate datetime
    ,@ToDate datetime

	DECLARE 
    @Distance_MTDCurrentMonth int
    ,@Distance_MTDLastMonth int
    ,@Distance_FullLastMonth int
    ,@Distance_MTDYear int
    
    IF @ReportDate IS NULL
    SELECT @Date_MTDCurrentMonth = GETDATE()
	ELSE
	BEGIN
		SELECT @Date_MTDCurrentMonth = @ReportDate
		SELECT @Date_MTDCurrentMonth = DATEADD(DAY, 1, @Date_MTDCurrentMonth)
	END

	SELECT @Date_MTDLastMonth = DATEADD(MONTH, -1, @Date_MTDCurrentMonth)

	SELECT  
		@Date_TheDayBefore = DATEADD(DAY, -1, @Date_MTDCurrentMonth)
		,@Date_FirstDayOfYear = DATEADD(yy, DATEDIFF(yy,0,@Date_TheDayBefore), 0)
		,@Date_FirstDayOfCurrentMonth = DATEADD(MONTH, DATEDIFF(MONTH,0,@Date_TheDayBefore), 0)
		,@Date_FirstDayOfLastMonth = DATEADD(MONTH, DATEDIFF(MONTH,0,@Date_TheDayBefore) - 1, 0)
    
	SELECT
		@Distance_MTDCurrentMonth = DATEDIFF(dd, @Date_FirstDayOfCurrentMonth, @Date_MTDCurrentMonth)
		,@Distance_MTDLastMonth = @Distance_MTDCurrentMonth
		,@Distance_FullLastMonth = DATEDIFF(dd, @Date_FirstDayOfLastMonth, @Date_FirstDayOfCurrentMonth)
		,@Distance_MTDYear = DATEDIFF(dd, @Date_FirstDayOfYear, @Date_MTDCurrentMonth)
		
	--get exchange just one time by longest range time
	
	SELECT exchangedate,exchangeid,EUR INTO #TempExchange 
	FROM bodb02.dbo.Lrf_f_GetExchangeDaily(@Date_FirstDayOfYear,DATEADD(DAY,-1,@Date_MTDCurrentMonth))
	WHERE EUR > 0

	--declare StatID params
	declare @Stat1003_CurrentDate varchar(50),
			@Stat1003_CurrentMonthToDate varchar(50),
			@Stat1003_LastMonthToDate varchar(50),
			@Stat1003_LastFullMonth varchar(50),
			@Stat1003_FullYearActual varchar(50),
	
			@Stat1004_CurrentDate varchar(50),
			@Stat1004_CurrentMonthToDate varchar(50),
			@Stat1004_LastMonthToDate varchar(50),
			@Stat1004_LastFullMonth varchar(50),
			@Stat1004_FullYearActual varchar(50),
			
			@Stat1005_CurrentDate varchar(50),
			@Stat1005_CurrentMonthToDate varchar(50),
			@Stat1005_LastMonthToDate varchar(50),
			@Stat1005_LastFullMonth varchar(50),
			@Stat1005_FullYearActual varchar(50),
			
			@Stat1006_CurrentDate varchar(50),
			@Stat1006_CurrentMonthToDate varchar(50),
			@Stat1006_LastMonthToDate varchar(50),
			@Stat1006_LastFullMonth varchar(50),
			@Stat1006_FullYearActual varchar(50),
			
			@Stat1007_CurrentDate varchar(50),
			@Stat1007_CurrentMonthToDate varchar(50),
			@Stat1007_LastMonthToDate varchar(50),
			@Stat1007_LastFullMonth varchar(50),
			@Stat1007_FullYearActual varchar(50),
			
			@Stat1008_CurrentDate varchar(50),
			@Stat1008_CurrentMonthToDate varchar(50),
			@Stat1008_LastMonthToDate varchar(50),
			@Stat1008_LastFullMonth varchar(50),
			@Stat1008_FullYearActual varchar(50)
		
	create table #TempResult
		(BranchID int,
		GroupID int,
		SectionID int,
		StatID int,
		CurrentDate varchar(50),
		CurrentMonthToDate varchar(50),
		CurrentFullMonthBudget varchar(50),
		LastMonthToDate varchar (50),
		LastFullMonth varchar(50),
		LastFullMonthBudget varchar(50),
		FullYearActual varchar(50),
		FullYearBudget varchar(50),
		FullYearDailyAverage varchar(50),
		FullYearMonthlyAverage varchar(50),
		FullYearThreeMonthDailyAverage varchar(50),
		FullYearThreeMonthAverage varchar(50)
		)


	--Normal case	
	IF (@BranchID <> @TempID AND @BranchID is not NULL)
	BEGIN
		--NormalType Group case
		IF (@TempType = 1)
		BEGIN
			insert into @Labels(LabelID,DateStarted)
				SELECT CASE WHEN lbl.licenseeid IS NULL THEN l.licenseeid ELSE lbl.LabelID END AS LabelID, 
					CASE WHEN lbl.licenseeid IS NULL THEN l.AffectedDate ELSE lbl.AffectedDate END AS AffectedDate
				FROM dbo.LicenseeReseller AS lr WITH (NOLOCK) LEFT OUTER JOIN
					dbo.Licensees AS l WITH (NOLOCK) ON lr.LicenseeID = l.LicenseeID LEFT OUTER JOIN
					dbo.Labels AS lbl WITH (NOLOCK) ON lr.LicenseeID = lbl.LicenseeID LEFT OUTER JOIN
					dbo.SystemLicensee AS syslic WITH (NOLOCK) ON lr.LicenseeID = syslic.LicenseeID
				WHERE (lr.ResellerID NOT IN (6,3)) AND (syslic.SystemID = 5) AND (syslic.IsActive = 1)
						AND (l.LicenseeID = @SiteID) AND (l.IsDeposit = 1)
	
			--Get data from bodb_licensee.dbo.rpt_Betting just one time by longest range time
			INSERT INTO #MTD_TopThreeSports(rptDate,CurrencyID,SportID,Turnover)
				SELECT rptDate,b.CurrencyID,l.sporttype,SUM(Turnover) Turnover  
				FROM bodb_LicenseeReport.dbo.rpt_Betting b (NOLOCK) 
					INNER JOIN bodb02.dbo.League l (NOLOCK) ON b.leagueid=l.leagueid 
			        INNER JOIN @Labels lbl ON b.SiteID=lbl.LabelID AND (lbl.DateStarted is null OR b.rptDate>=lbl.DateStarted)
				WHERE rptDate>=@Date_FirstDayOfYear AND rptDate<@Date_MTDCurrentMonth
					AND b.status NOT IN (-1,103) 
					AND b.currencyID<>20 
					AND (Bettype < 31 OR (Bettype >= 121 AND Bettype < 1000))
					AND ISNULL(b.customercategory,-1) NOT IN (27,28)
				GROUP BY rptDate,b.CurrencyID,l.sporttype
					
			--GET DATA INTO PARAMS
			--For current date
			SELECT @FromDate = @Date_TheDayBefore, @ToDate = @Date_MTDCurrentMonth
			
			insert INTO #TopThreeSportsResult (SportRank, SportName, TurnOverPercentage)
			SELECT TOP(3)
				ROW_NUMBER() OVER (Order by SUM(tmp.PercentTurnover) DESC) AS SportRank
				,s.SportName AS SportName
				,ISNULL(SUM(tmp.PercentTurnover),0)/(1) AS TurnOverPercentage
				FROM bodb02.dbo.Sports s (NOLOCK)
			INNER JOIN (
			SELECT mtd.rptDate
				,mtd.SportID
				,SUM(mtd.Turnover*EUR)/SUM(total.TotalTurnover*EUR) PercentTurnover
			FROM #MTD_TopThreeSports mtd (NOLOCK)
				INNER JOIN #TempExchange e ON mtd.currencyID = e.exchangeid AND mtd.rptdate = e.exchangedate 
				INNER JOIN (SELECT rptDate,CurrencyID,SUM(Turnover) AS TotalTurnover
							FROM #MTD_TopThreeSports (NOLOCK)
							WHERE rptDate>=@FromDate AND rptDate<@ToDate
							GROUP BY rptDate,CurrencyID) total 
				ON mtd.rptDate = total.rptDate AND mtd.currencyID = total.CurrencyID
			WHERE mtd.rptDate>=@FromDate AND mtd.rptDate<@ToDate
			GROUP BY mtd.rptDate,SportID
			) tmp ON s.SportType = tmp.SportID
			GROUP BY s.SportName
			ORDER BY SUM(tmp.PercentTurnover) DESC
			
			select @Stat1003_CurrentDate = SportName, @Stat1004_CurrentDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 1
			
			select @Stat1005_CurrentDate = SportName, @Stat1006_CurrentDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 2
			
			select @Stat1007_CurrentDate = SportName, @Stat1008_CurrentDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 3
								
			--For current month to date
			SELECT @FromDate = @Date_FirstDayOfCurrentMonth, @ToDate = @Date_MTDCurrentMonth
			
			delete FROM #TopThreeSportsResult
			insert INTO #TopThreeSportsResult (SportRank, SportName, TurnOverPercentage)
			SELECT TOP(3)
				ROW_NUMBER() OVER (Order by SUM(tmp.PercentTurnover) DESC) AS SportRank
				,s.SportName AS SportName
				,ISNULL(SUM(tmp.PercentTurnover),0)/(@Distance_MTDCurrentMonth) AS TurnOverPercentage
				FROM bodb02.dbo.Sports s (NOLOCK)
			INNER JOIN (
			SELECT mtd.rptDate
				,mtd.SportID
				,SUM(mtd.Turnover*EUR)/SUM(total.TotalTurnover*EUR) PercentTurnover
			FROM #MTD_TopThreeSports mtd (NOLOCK)
				INNER JOIN #TempExchange e ON mtd.currencyID = e.exchangeid AND mtd.rptdate = e.exchangedate 
				INNER JOIN (SELECT rptDate,CurrencyID,SUM(Turnover) AS TotalTurnover
							FROM #MTD_TopThreeSports (NOLOCK)
							WHERE rptDate>=@FromDate AND rptDate<@ToDate
							GROUP BY rptDate,CurrencyID) total 
				ON mtd.rptDate = total.rptDate AND mtd.currencyID = total.CurrencyID
			WHERE mtd.rptDate>=@FromDate AND mtd.rptDate<@ToDate
			GROUP BY mtd.rptDate,SportID
			) tmp ON s.SportType = tmp.SportID
			GROUP BY s.SportName
			ORDER BY SUM(tmp.PercentTurnover) DESC
			
			select @Stat1003_CurrentMonthToDate = SportName, @Stat1004_CurrentMonthToDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 1
			
			select @Stat1005_CurrentMonthToDate = SportName, @Stat1006_CurrentMonthToDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 2
			
			select @Stat1007_CurrentMonthToDate = SportName, @Stat1008_CurrentMonthToDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 3
						
			--For last month to date
			SELECT @FromDate = @Date_FirstDayOfLastMonth, @ToDate = @Date_MTDLastMonth
			
			insert INTO #TopThreeSportsResult (SportRank, SportName, TurnOverPercentage)
			SELECT TOP(3)
				ROW_NUMBER() OVER (Order by SUM(tmp.PercentTurnover) DESC) AS SportRank
				,s.SportName AS SportName
				,ISNULL(SUM(tmp.PercentTurnover),0)/(@Distance_MTDLastMonth) AS TurnOverPercentage
				FROM bodb02.dbo.Sports s (NOLOCK)
			INNER JOIN (
			SELECT mtd.rptDate
				,mtd.SportID
				,SUM(mtd.Turnover*EUR)/SUM(total.TotalTurnover*EUR) PercentTurnover
			FROM #MTD_TopThreeSports mtd (NOLOCK)
				INNER JOIN #TempExchange e ON mtd.currencyID = e.exchangeid AND mtd.rptdate = e.exchangedate 
				INNER JOIN (SELECT rptDate,CurrencyID,SUM(Turnover) AS TotalTurnover
							FROM #MTD_TopThreeSports (NOLOCK)
							WHERE rptDate>=@FromDate AND rptDate<@ToDate
							GROUP BY rptDate,CurrencyID) total 
				ON mtd.rptDate = total.rptDate AND mtd.currencyID = total.CurrencyID
			WHERE mtd.rptDate>=@FromDate AND mtd.rptDate<@ToDate
			GROUP BY mtd.rptDate,SportID
			) tmp ON s.SportType = tmp.SportID
			GROUP BY s.SportName
			ORDER BY SUM(tmp.PercentTurnover) DESC
			
			select @Stat1003_LastMonthToDate = SportName, @Stat1004_LastMonthToDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 1
			
			select @Stat1005_LastMonthToDate = SportName, @Stat1006_LastMonthToDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 2
			
			select @Stat1007_LastMonthToDate = SportName, @Stat1008_LastMonthToDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 3
						
			--For last full month
			SELECT @FromDate = @Date_FirstDayOfLastMonth, @ToDate = @Date_FirstDayOfCurrentMonth
			
			insert INTO #TopThreeSportsResult (SportRank, SportName, TurnOverPercentage)
			SELECT TOP(3)
				ROW_NUMBER() OVER (Order by SUM(tmp.PercentTurnover) DESC) AS SportRank
				,s.SportName AS SportName
				,ISNULL(SUM(tmp.PercentTurnover),0)/(@Distance_FullLastMonth) AS TurnOverPercentage
				FROM bodb02.dbo.Sports s (NOLOCK)
			INNER JOIN (
			SELECT mtd.rptDate
				,mtd.SportID
				,SUM(mtd.Turnover*EUR)/SUM(total.TotalTurnover*EUR) PercentTurnover
			FROM #MTD_TopThreeSports mtd (NOLOCK)
				INNER JOIN #TempExchange e ON mtd.currencyID = e.exchangeid AND mtd.rptdate = e.exchangedate 
				INNER JOIN (SELECT rptDate,CurrencyID,SUM(Turnover) AS TotalTurnover
							FROM #MTD_TopThreeSports (NOLOCK)
							WHERE rptDate>=@FromDate AND rptDate<@ToDate
							GROUP BY rptDate,CurrencyID) total 
				ON mtd.rptDate = total.rptDate AND mtd.currencyID = total.CurrencyID
			WHERE mtd.rptDate>=@FromDate AND mtd.rptDate<@ToDate
			GROUP BY mtd.rptDate,SportID
			) tmp ON s.SportType = tmp.SportID
			GROUP BY s.SportName
			ORDER BY SUM(tmp.PercentTurnover) DESC
			
			select @Stat1003_LastFullMonth = SportName, @Stat1004_LastFullMonth = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 1
			
			select @Stat1005_LastFullMonth = SportName, @Stat1006_LastFullMonth = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 2
			
			select @Stat1007_LastFullMonth = SportName, @Stat1008_LastFullMonth = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 3
					
			--For full year actual
			SELECT @FromDate = @Date_FirstDayOfYear, @ToDate = @Date_MTDCurrentMonth
			
			insert INTO #TopThreeSportsResult (SportRank, SportName, TurnOverPercentage)
			SELECT TOP(3)
				ROW_NUMBER() OVER (Order by SUM(tmp.PercentTurnover) DESC) AS SportRank
				,s.SportName AS SportName
				,ISNULL(SUM(tmp.PercentTurnover),0)/(@Distance_MTDYear) AS TurnOverPercentage
				FROM bodb02.dbo.Sports s (NOLOCK)
			INNER JOIN (
			SELECT mtd.rptDate
				,mtd.SportID
				,SUM(mtd.Turnover*EUR)/SUM(total.TotalTurnover*EUR) PercentTurnover
			FROM #MTD_TopThreeSports mtd (NOLOCK)
				INNER JOIN #TempExchange e ON mtd.currencyID = e.exchangeid AND mtd.rptdate = e.exchangedate 
				INNER JOIN (SELECT rptDate,CurrencyID,SUM(Turnover) AS TotalTurnover
							FROM #MTD_TopThreeSports (NOLOCK)
							WHERE rptDate>=@FromDate AND rptDate<@ToDate
							GROUP BY rptDate,CurrencyID) total 
				ON mtd.rptDate = total.rptDate AND mtd.currencyID = total.CurrencyID
			WHERE mtd.rptDate>=@FromDate AND mtd.rptDate<@ToDate
			GROUP BY mtd.rptDate,SportID
			) tmp ON s.SportType = tmp.SportID
			GROUP BY s.SportName
			ORDER BY SUM(tmp.PercentTurnover) DESC
			
			select @Stat1003_FullYearActual = SportName, @Stat1004_FullYearActual = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 1
			
			select @Stat1005_FullYearActual = SportName, @Stat1006_FullYearActual = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 2
			
			select @Stat1007_FullYearActual = SportName, @Stat1008_FullYearActual = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 3		
							
		END
		--SummaryType Group case
		ELSE
		BEGIN
			insert into @Labels(LabelID,DateStarted)
				SELECT CASE WHEN lbl.licenseeid IS NULL THEN l.licenseeid ELSE lbl.LabelID END AS LabelID, 
					CASE WHEN lbl.licenseeid IS NULL THEN l.AffectedDate ELSE lbl.AffectedDate END AS AffectedDate
				FROM dbo.LicenseeReseller AS lr WITH (NOLOCK) LEFT OUTER JOIN
					dbo.Licensees AS l WITH (NOLOCK) ON lr.LicenseeID = l.LicenseeID LEFT OUTER JOIN
					dbo.Labels AS lbl WITH (NOLOCK) ON lr.LicenseeID = lbl.LicenseeID LEFT OUTER JOIN
					dbo.SystemLicensee AS syslic WITH (NOLOCK) ON lr.LicenseeID = syslic.LicenseeID
				WHERE (lr.ResellerID NOT IN (6,3)) AND (syslic.SystemID = 5) AND (syslic.IsActive = 1)
					   AND (l.IsDeposit = 1)
	
			--Get data from bodb_licensee.dbo.rpt_Betting just one time by longest range time
			INSERT INTO #MTD_TopThreeSports(rptDate,CurrencyID,SportID,Turnover)
				SELECT rptDate,b.CurrencyID,l.sporttype,SUM(Turnover) Turnover  
				FROM (
						SELECT rptDate,LeagueID,SiteID,CurrencyID,Turnover
						FROM bodb_LicenseeReport.dbo.rpt_Betting (NOLOCK) 
						WHERE rptDate>=@Date_FirstDayOfYear AND rptDate<@Date_MTDCurrentMonth
							AND status NOT IN (-1,103) 
							AND currencyID<>20 
							AND (Bettype < 31 OR (Bettype >= 121 AND Bettype < 1000))
							AND ISNULL(customercategory,-1) NOT IN (27,28)-- 8RM&BARM 
						UNION ALL
						SELECT rptDate,LeagueID,SiteID,CurrencyID,Turnover
						FROM bodb_LicenseeReport.dbo.rpt_Betting_BA (NOLOCK) 
						WHERE rptDate>=@Date_FirstDayOfYear AND rptDate<@Date_MTDCurrentMonth
							AND status NOT IN (-1,103) 
							AND currencyID<>20 
							AND (Bettype < 31 OR (Bettype >= 121 AND Bettype < 1000))
					 ) b 
					INNER JOIN bodb02.dbo.League l (NOLOCK) ON b.leagueid=l.leagueid 
			        INNER JOIN @Labels lbl ON b.SiteID=lbl.LabelID AND (lbl.DateStarted is null OR b.rptDate>=lbl.DateStarted)
				GROUP BY rptDate,b.CurrencyID,l.sporttype
					
			--GET DATA INTO PARAMS
			--For current date
			SELECT @FromDate = @Date_TheDayBefore, @ToDate = @Date_MTDCurrentMonth
			
			insert INTO #TopThreeSportsResult (SportRank, SportName, TurnOverPercentage)
			SELECT TOP(3)
				ROW_NUMBER() OVER (Order by SUM(tmp.PercentTurnover) DESC) AS SportRank
				,s.SportName AS SportName
				,ISNULL(SUM(tmp.PercentTurnover),0)/(1) AS TurnOverPercentage
				FROM bodb02.dbo.Sports s (NOLOCK)
			INNER JOIN (
			SELECT mtd.rptDate
				,mtd.SportID
				,SUM(mtd.Turnover*EUR)/SUM(total.TotalTurnover*EUR) PercentTurnover
			FROM #MTD_TopThreeSports mtd (NOLOCK)
				INNER JOIN #TempExchange e ON mtd.currencyID = e.exchangeid AND mtd.rptdate = e.exchangedate 
				INNER JOIN (SELECT rptDate,CurrencyID,SUM(Turnover) AS TotalTurnover
							FROM #MTD_TopThreeSports (NOLOCK)
							WHERE rptDate>=@FromDate AND rptDate<@ToDate
							GROUP BY rptDate,CurrencyID) total 
				ON mtd.rptDate = total.rptDate AND mtd.currencyID = total.CurrencyID
			WHERE mtd.rptDate>=@FromDate AND mtd.rptDate<@ToDate
			GROUP BY mtd.rptDate,SportID
			) tmp ON s.SportType = tmp.SportID
			GROUP BY s.SportName
			ORDER BY SUM(tmp.PercentTurnover) DESC
			
			select @Stat1003_CurrentDate = SportName, @Stat1004_CurrentDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 1
			
			select @Stat1005_CurrentDate = SportName, @Stat1006_CurrentDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 2
			
			select @Stat1007_CurrentDate = SportName, @Stat1008_CurrentDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 3
								
			--For current month to date
			SELECT @FromDate = @Date_FirstDayOfCurrentMonth, @ToDate = @Date_MTDCurrentMonth
			
			delete FROM #TopThreeSportsResult
			insert INTO #TopThreeSportsResult (SportRank, SportName, TurnOverPercentage)
			SELECT TOP(3)
				ROW_NUMBER() OVER (Order by SUM(tmp.PercentTurnover) DESC) AS SportRank
				,s.SportName AS SportName
				,ISNULL(SUM(tmp.PercentTurnover),0)/(@Distance_MTDCurrentMonth) AS TurnOverPercentage
				FROM bodb02.dbo.Sports s (NOLOCK)
			INNER JOIN (
			SELECT mtd.rptDate
				,mtd.SportID
				,SUM(mtd.Turnover*EUR)/SUM(total.TotalTurnover*EUR) PercentTurnover
			FROM #MTD_TopThreeSports mtd (NOLOCK)
				INNER JOIN #TempExchange e ON mtd.currencyID = e.exchangeid AND mtd.rptdate = e.exchangedate 
				INNER JOIN (SELECT rptDate,CurrencyID,SUM(Turnover) AS TotalTurnover
							FROM #MTD_TopThreeSports (NOLOCK)
							WHERE rptDate>=@FromDate AND rptDate<@ToDate
							GROUP BY rptDate,CurrencyID) total 
				ON mtd.rptDate = total.rptDate AND mtd.currencyID = total.CurrencyID
			WHERE mtd.rptDate>=@FromDate AND mtd.rptDate<@ToDate
			GROUP BY mtd.rptDate,SportID
			) tmp ON s.SportType = tmp.SportID
			GROUP BY s.SportName
			ORDER BY SUM(tmp.PercentTurnover) DESC
			
			select @Stat1003_CurrentMonthToDate = SportName, @Stat1004_CurrentMonthToDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 1
			
			select @Stat1005_CurrentMonthToDate = SportName, @Stat1006_CurrentMonthToDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 2
			
			select @Stat1007_CurrentMonthToDate = SportName, @Stat1008_CurrentMonthToDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 3
						
			--For last month to date
			SELECT @FromDate = @Date_FirstDayOfLastMonth, @ToDate = @Date_MTDLastMonth
			
			insert INTO #TopThreeSportsResult (SportRank, SportName, TurnOverPercentage)
			SELECT TOP(3)
				ROW_NUMBER() OVER (Order by SUM(tmp.PercentTurnover) DESC) AS SportRank
				,s.SportName AS SportName
				,ISNULL(SUM(tmp.PercentTurnover),0)/(@Distance_MTDLastMonth) AS TurnOverPercentage
				FROM bodb02.dbo.Sports s (NOLOCK)
			INNER JOIN (
			SELECT mtd.rptDate
				,mtd.SportID
				,SUM(mtd.Turnover*EUR)/SUM(total.TotalTurnover*EUR) PercentTurnover
			FROM #MTD_TopThreeSports mtd (NOLOCK)
				INNER JOIN #TempExchange e ON mtd.currencyID = e.exchangeid AND mtd.rptdate = e.exchangedate 
				INNER JOIN (SELECT rptDate,CurrencyID,SUM(Turnover) AS TotalTurnover
							FROM #MTD_TopThreeSports (NOLOCK)
							WHERE rptDate>=@FromDate AND rptDate<@ToDate
							GROUP BY rptDate,CurrencyID) total 
				ON mtd.rptDate = total.rptDate AND mtd.currencyID = total.CurrencyID
			WHERE mtd.rptDate>=@FromDate AND mtd.rptDate<@ToDate
			GROUP BY mtd.rptDate,SportID
			) tmp ON s.SportType = tmp.SportID
			GROUP BY s.SportName
			ORDER BY SUM(tmp.PercentTurnover) DESC
			
			select @Stat1003_LastMonthToDate = SportName, @Stat1004_LastMonthToDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 1
			
			select @Stat1005_LastMonthToDate = SportName, @Stat1006_LastMonthToDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 2
			
			select @Stat1007_LastMonthToDate = SportName, @Stat1008_LastMonthToDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 3
						
			--For last full month
			SELECT @FromDate = @Date_FirstDayOfLastMonth, @ToDate = @Date_FirstDayOfCurrentMonth
			
			insert INTO #TopThreeSportsResult (SportRank, SportName, TurnOverPercentage)
			SELECT TOP(3)
				ROW_NUMBER() OVER (Order by SUM(tmp.PercentTurnover) DESC) AS SportRank
				,s.SportName AS SportName
				,ISNULL(SUM(tmp.PercentTurnover),0)/(@Distance_FullLastMonth) AS TurnOverPercentage
				FROM bodb02.dbo.Sports s (NOLOCK)
			INNER JOIN (
			SELECT mtd.rptDate
				,mtd.SportID
				,SUM(mtd.Turnover*EUR)/SUM(total.TotalTurnover*EUR) PercentTurnover
			FROM #MTD_TopThreeSports mtd (NOLOCK)
				INNER JOIN #TempExchange e ON mtd.currencyID = e.exchangeid AND mtd.rptdate = e.exchangedate 
				INNER JOIN (SELECT rptDate,CurrencyID,SUM(Turnover) AS TotalTurnover
							FROM #MTD_TopThreeSports (NOLOCK)
							WHERE rptDate>=@FromDate AND rptDate<@ToDate
							GROUP BY rptDate,CurrencyID) total 
				ON mtd.rptDate = total.rptDate AND mtd.currencyID = total.CurrencyID
			WHERE mtd.rptDate>=@FromDate AND mtd.rptDate<@ToDate
			GROUP BY mtd.rptDate,SportID
			) tmp ON s.SportType = tmp.SportID
			GROUP BY s.SportName
			ORDER BY SUM(tmp.PercentTurnover) DESC
			
			select @Stat1003_LastFullMonth = SportName, @Stat1004_LastFullMonth = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 1
			
			select @Stat1005_LastFullMonth = SportName, @Stat1006_LastFullMonth = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 2
			
			select @Stat1007_LastFullMonth = SportName, @Stat1008_LastFullMonth = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 3
					
			--For full year actual
			SELECT @FromDate = @Date_FirstDayOfYear, @ToDate = @Date_MTDCurrentMonth
			
			insert INTO #TopThreeSportsResult (SportRank, SportName, TurnOverPercentage)
			SELECT TOP(3)
				ROW_NUMBER() OVER (Order by SUM(tmp.PercentTurnover) DESC) AS SportRank
				,s.SportName AS SportName
				,ISNULL(SUM(tmp.PercentTurnover),0)/(@Distance_MTDYear) AS TurnOverPercentage
				FROM bodb02.dbo.Sports s (NOLOCK)
			INNER JOIN (
			SELECT mtd.rptDate
				,mtd.SportID
				,SUM(mtd.Turnover*EUR)/SUM(total.TotalTurnover*EUR) PercentTurnover
			FROM #MTD_TopThreeSports mtd (NOLOCK)
				INNER JOIN #TempExchange e ON mtd.currencyID = e.exchangeid AND mtd.rptdate = e.exchangedate 
				INNER JOIN (SELECT rptDate,CurrencyID,SUM(Turnover) AS TotalTurnover
							FROM #MTD_TopThreeSports (NOLOCK)
							WHERE rptDate>=@FromDate AND rptDate<@ToDate
							GROUP BY rptDate,CurrencyID) total 
				ON mtd.rptDate = total.rptDate AND mtd.currencyID = total.CurrencyID
			WHERE mtd.rptDate>=@FromDate AND mtd.rptDate<@ToDate
			GROUP BY mtd.rptDate,SportID
			) tmp ON s.SportType = tmp.SportID
			GROUP BY s.SportName
			ORDER BY SUM(tmp.PercentTurnover) DESC
			
			select @Stat1003_FullYearActual = SportName, @Stat1004_FullYearActual = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 1
			
			select @Stat1005_FullYearActual = SportName, @Stat1006_FullYearActual = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 2
			
			select @Stat1007_FullYearActual = SportName, @Stat1008_FullYearActual = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 3		
			
			
			
		END
	END
	
	--BA case
	IF (@BranchID = @TempID and @BranchID is not NULL)
	BEGIN
			insert into @Labels(LabelID,DateStarted)
				SELECT CASE WHEN lbl.licenseeid IS NULL THEN l.licenseeid ELSE lbl.LabelID END AS LabelID, 
					CASE WHEN lbl.licenseeid IS NULL THEN l.AffectedDate ELSE lbl.AffectedDate END AS AffectedDate
				FROM dbo.LicenseeReseller AS lr WITH (NOLOCK) LEFT OUTER JOIN
					dbo.Licensees AS l WITH (NOLOCK) ON lr.LicenseeID = l.LicenseeID LEFT OUTER JOIN
					dbo.Labels AS lbl WITH (NOLOCK) ON lr.LicenseeID = lbl.LicenseeID LEFT OUTER JOIN
					dbo.SystemLicensee AS syslic WITH (NOLOCK) ON lr.LicenseeID = syslic.LicenseeID
				WHERE (lr.ResellerID = 3) AND (syslic.SystemID = 5) AND (syslic.IsActive = 1)
						AND (l.LicenseeID = @SiteID) AND (l.IsDeposit = 1)
	
			--Get data from bodb_licensee.dbo.rpt_Betting just one time by longest range time
			INSERT INTO #MTD_TopThreeSports(rptDate,CurrencyID,SportID,Turnover)
				SELECT rptDate,b.CurrencyID,l.sporttype,SUM(Turnover) Turnover  
				FROM bodb_LicenseeReport.dbo.rpt_Betting_BA b (NOLOCK) 
					INNER JOIN bodb02.dbo.League l (NOLOCK) ON b.leagueid=l.leagueid 
			        INNER JOIN @Labels lbl ON b.SiteID=lbl.LabelID AND (lbl.DateStarted is null OR b.rptDate>=lbl.DateStarted)
				WHERE rptDate>=@Date_FirstDayOfYear AND rptDate<@Date_MTDCurrentMonth
					AND b.status NOT IN (-1,103) 
					AND b.currencyID<>20 
					AND (Bettype < 31 OR (Bettype >= 121 AND Bettype < 1000))
				GROUP BY rptDate,b.CurrencyID,l.sporttype
					
			--GET DATA INTO PARAMS
			--For current date
			SELECT @FromDate = @Date_TheDayBefore, @ToDate = @Date_MTDCurrentMonth
			
			insert INTO #TopThreeSportsResult (SportRank, SportName, TurnOverPercentage)
			SELECT TOP(3)
				ROW_NUMBER() OVER (Order by SUM(tmp.PercentTurnover) DESC) AS SportRank
				,s.SportName AS SportName
				,ISNULL(SUM(tmp.PercentTurnover),0)/(1) AS TurnOverPercentage
				FROM bodb02.dbo.Sports s (NOLOCK)
			INNER JOIN (
			SELECT mtd.rptDate
				,mtd.SportID
				,SUM(mtd.Turnover*EUR)/SUM(total.TotalTurnover*EUR) PercentTurnover
			FROM #MTD_TopThreeSports mtd (NOLOCK)
				INNER JOIN #TempExchange e ON mtd.currencyID = e.exchangeid AND mtd.rptdate = e.exchangedate 
				INNER JOIN (SELECT rptDate,CurrencyID,SUM(Turnover) AS TotalTurnover
							FROM #MTD_TopThreeSports (NOLOCK)
							WHERE rptDate>=@FromDate AND rptDate<@ToDate
							GROUP BY rptDate,CurrencyID) total 
				ON mtd.rptDate = total.rptDate AND mtd.currencyID = total.CurrencyID
			WHERE mtd.rptDate>=@FromDate AND mtd.rptDate<@ToDate
			GROUP BY mtd.rptDate,SportID
			) tmp ON s.SportType = tmp.SportID
			GROUP BY s.SportName
			ORDER BY SUM(tmp.PercentTurnover) DESC
			
			select @Stat1003_CurrentDate = SportName, @Stat1004_CurrentDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 1
			
			select @Stat1005_CurrentDate = SportName, @Stat1006_CurrentDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 2
			
			select @Stat1007_CurrentDate = SportName, @Stat1008_CurrentDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 3
								
			--For current month to date
			SELECT @FromDate = @Date_FirstDayOfCurrentMonth, @ToDate = @Date_MTDCurrentMonth
			
			delete FROM #TopThreeSportsResult
			insert INTO #TopThreeSportsResult (SportRank, SportName, TurnOverPercentage)
			SELECT TOP(3)
				ROW_NUMBER() OVER (Order by SUM(tmp.PercentTurnover) DESC) AS SportRank
				,s.SportName AS SportName
				,ISNULL(SUM(tmp.PercentTurnover),0)/(@Distance_MTDCurrentMonth) AS TurnOverPercentage
				FROM bodb02.dbo.Sports s (NOLOCK)
			INNER JOIN (
			SELECT mtd.rptDate
				,mtd.SportID
				,SUM(mtd.Turnover*EUR)/SUM(total.TotalTurnover*EUR) PercentTurnover
			FROM #MTD_TopThreeSports mtd (NOLOCK)
				INNER JOIN #TempExchange e ON mtd.currencyID = e.exchangeid AND mtd.rptdate = e.exchangedate 
				INNER JOIN (SELECT rptDate,CurrencyID,SUM(Turnover) AS TotalTurnover
							FROM #MTD_TopThreeSports (NOLOCK)
							WHERE rptDate>=@FromDate AND rptDate<@ToDate
							GROUP BY rptDate,CurrencyID) total 
				ON mtd.rptDate = total.rptDate AND mtd.currencyID = total.CurrencyID
			WHERE mtd.rptDate>=@FromDate AND mtd.rptDate<@ToDate
			GROUP BY mtd.rptDate,SportID
			) tmp ON s.SportType = tmp.SportID
			GROUP BY s.SportName
			ORDER BY SUM(tmp.PercentTurnover) DESC
			
			select @Stat1003_CurrentMonthToDate = SportName, @Stat1004_CurrentMonthToDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 1
			
			select @Stat1005_CurrentMonthToDate = SportName, @Stat1006_CurrentMonthToDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 2
			
			select @Stat1007_CurrentMonthToDate = SportName, @Stat1008_CurrentMonthToDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 3
						
			--For last month to date
			SELECT @FromDate = @Date_FirstDayOfLastMonth, @ToDate = @Date_MTDLastMonth
			
			insert INTO #TopThreeSportsResult (SportRank, SportName, TurnOverPercentage)
			SELECT TOP(3)
				ROW_NUMBER() OVER (Order by SUM(tmp.PercentTurnover) DESC) AS SportRank
				,s.SportName AS SportName
				,ISNULL(SUM(tmp.PercentTurnover),0)/(@Distance_MTDLastMonth) AS TurnOverPercentage
				FROM bodb02.dbo.Sports s (NOLOCK)
			INNER JOIN (
			SELECT mtd.rptDate
				,mtd.SportID
				,SUM(mtd.Turnover*EUR)/SUM(total.TotalTurnover*EUR) PercentTurnover
			FROM #MTD_TopThreeSports mtd (NOLOCK)
				INNER JOIN #TempExchange e ON mtd.currencyID = e.exchangeid AND mtd.rptdate = e.exchangedate 
				INNER JOIN (SELECT rptDate,CurrencyID,SUM(Turnover) AS TotalTurnover
							FROM #MTD_TopThreeSports (NOLOCK)
							WHERE rptDate>=@FromDate AND rptDate<@ToDate
							GROUP BY rptDate,CurrencyID) total 
				ON mtd.rptDate = total.rptDate AND mtd.currencyID = total.CurrencyID
			WHERE mtd.rptDate>=@FromDate AND mtd.rptDate<@ToDate
			GROUP BY mtd.rptDate,SportID
			) tmp ON s.SportType = tmp.SportID
			GROUP BY s.SportName
			ORDER BY SUM(tmp.PercentTurnover) DESC
			
			select @Stat1003_LastMonthToDate = SportName, @Stat1004_LastMonthToDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 1
			
			select @Stat1005_LastMonthToDate = SportName, @Stat1006_LastMonthToDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 2
			
			select @Stat1007_LastMonthToDate = SportName, @Stat1008_LastMonthToDate = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 3
						
			--For last full month
			SELECT @FromDate = @Date_FirstDayOfLastMonth, @ToDate = @Date_FirstDayOfCurrentMonth
			
			insert INTO #TopThreeSportsResult (SportRank, SportName, TurnOverPercentage)
			SELECT TOP(3)
				ROW_NUMBER() OVER (Order by SUM(tmp.PercentTurnover) DESC) AS SportRank
				,s.SportName AS SportName
				,ISNULL(SUM(tmp.PercentTurnover),0)/(@Distance_FullLastMonth) AS TurnOverPercentage
				FROM bodb02.dbo.Sports s (NOLOCK)
			INNER JOIN (
			SELECT mtd.rptDate
				,mtd.SportID
				,SUM(mtd.Turnover*EUR)/SUM(total.TotalTurnover*EUR) PercentTurnover
			FROM #MTD_TopThreeSports mtd (NOLOCK)
				INNER JOIN #TempExchange e ON mtd.currencyID = e.exchangeid AND mtd.rptdate = e.exchangedate 
				INNER JOIN (SELECT rptDate,CurrencyID,SUM(Turnover) AS TotalTurnover
							FROM #MTD_TopThreeSports (NOLOCK)
							WHERE rptDate>=@FromDate AND rptDate<@ToDate
							GROUP BY rptDate,CurrencyID) total 
				ON mtd.rptDate = total.rptDate AND mtd.currencyID = total.CurrencyID
			WHERE mtd.rptDate>=@FromDate AND mtd.rptDate<@ToDate
			GROUP BY mtd.rptDate,SportID
			) tmp ON s.SportType = tmp.SportID
			GROUP BY s.SportName
			ORDER BY SUM(tmp.PercentTurnover) DESC
			
			select @Stat1003_LastFullMonth = SportName, @Stat1004_LastFullMonth = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 1
			
			select @Stat1005_LastFullMonth = SportName, @Stat1006_LastFullMonth = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 2
			
			select @Stat1007_LastFullMonth = SportName, @Stat1008_LastFullMonth = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 3
					
			--For full year actual
			SELECT @FromDate = @Date_FirstDayOfYear, @ToDate = @Date_MTDCurrentMonth
			
			insert INTO #TopThreeSportsResult (SportRank, SportName, TurnOverPercentage)
			SELECT TOP(3)
				ROW_NUMBER() OVER (Order by SUM(tmp.PercentTurnover) DESC) AS SportRank
				,s.SportName AS SportName
				,ISNULL(SUM(tmp.PercentTurnover),0)/(@Distance_MTDYear) AS TurnOverPercentage
				FROM bodb02.dbo.Sports s (NOLOCK)
			INNER JOIN (
			SELECT mtd.rptDate
				,mtd.SportID
				,SUM(mtd.Turnover*EUR)/SUM(total.TotalTurnover*EUR) PercentTurnover
			FROM #MTD_TopThreeSports mtd (NOLOCK)
				INNER JOIN #TempExchange e ON mtd.currencyID = e.exchangeid AND mtd.rptdate = e.exchangedate 
				INNER JOIN (SELECT rptDate,CurrencyID,SUM(Turnover) AS TotalTurnover
							FROM #MTD_TopThreeSports (NOLOCK)
							WHERE rptDate>=@FromDate AND rptDate<@ToDate
							GROUP BY rptDate,CurrencyID) total 
				ON mtd.rptDate = total.rptDate AND mtd.currencyID = total.CurrencyID
			WHERE mtd.rptDate>=@FromDate AND mtd.rptDate<@ToDate
			GROUP BY mtd.rptDate,SportID
			) tmp ON s.SportType = tmp.SportID
			GROUP BY s.SportName
			ORDER BY SUM(tmp.PercentTurnover) DESC
			
			select @Stat1003_FullYearActual = SportName, @Stat1004_FullYearActual = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 1
			
			select @Stat1005_FullYearActual = SportName, @Stat1006_FullYearActual = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 2
			
			select @Stat1007_FullYearActual = SportName, @Stat1008_FullYearActual = CAST(TurnOverPercentage AS varchar(50))
			from #TopThreeSportsResult (NOLOCK)
			where SportRank = 3		
	END
	
	--case when there is no top 1 sport
	if (@Stat1003_FullYearActual is null)
	begin
		select BranchID,GroupID,SectionID,StatID,CurrentDate,CurrentMonthToDate,CurrentFullMonthBudget,LastMonthToDate,
			   LastFullMonth,LastFullMonthBudget,FullYearActual,FullYearBudget,FullYearDailyAverage,
			   FullYearMonthlyAverage,FullYearThreeMonthDailyAverage,FullYearThreeMonthAverage
		from #TempResult (NOLOCK)
	end
	else
	begin
		insert into #TempResult
			   (BranchID,GroupID,SectionID,StatID,CurrentDate,CurrentMonthToDate,CurrentFullMonthBudget,LastMonthToDate,
			   LastFullMonth,LastFullMonthBudget,FullYearActual,FullYearBudget,FullYearDailyAverage,
			   FullYearMonthlyAverage,FullYearThreeMonthDailyAverage,FullYearThreeMonthAverage)
		SELECT @BranchID,@GroupID,@SectionID,1003,@Stat1003_CurrentDate,@Stat1003_CurrentMonthToDate,NULL,
			   @Stat1003_LastMonthToDate,@Stat1003_LastFullMonth,NULL,@Stat1003_FullYearActual,NULL,NULL,NULL,NULL,NULL
		UNION ALL
		SELECT @BranchID,@GroupID,@SectionID,1004,@Stat1004_CurrentDate,@Stat1004_CurrentMonthToDate,NULL,
			   @Stat1004_LastMonthToDate,@Stat1004_LastFullMonth,NULL,@Stat1004_FullYearActual,NULL,NULL,NULL,NULL,NULL
		UNION ALL
		SELECT @BranchID,@GroupID,@SectionID,1005,@Stat1005_CurrentDate,@Stat1005_CurrentMonthToDate,NULL,
			   @Stat1005_LastMonthToDate,@Stat1005_LastFullMonth,NULL,@Stat1005_FullYearActual,NULL,NULL,NULL,NULL,NULL
		UNION ALL
		SELECT @BranchID,@GroupID,@SectionID,1006,@Stat1006_CurrentDate,@Stat1006_CurrentMonthToDate,NULL,
			   @Stat1006_LastMonthToDate,@Stat1006_LastFullMonth,NULL,@Stat1006_FullYearActual,NULL,NULL,NULL,NULL,NULL
		UNION ALL
		SELECT @BranchID,@GroupID,@SectionID,1007,@Stat1007_CurrentDate,@Stat1007_CurrentMonthToDate,NULL,
			   @Stat1007_LastMonthToDate,@Stat1007_LastFullMonth,NULL,@Stat1007_FullYearActual,NULL,NULL,NULL,NULL,NULL
		UNION ALL
		SELECT @BranchID,@GroupID,@SectionID,1008,@Stat1008_CurrentDate,@Stat1008_CurrentMonthToDate,NULL,
			   @Stat1008_LastMonthToDate,@Stat1008_LastFullMonth,NULL,@Stat1008_FullYearActual,NULL,NULL,NULL,NULL,NULL
			   
		SELECT BranchID,GroupID,SectionID,StatID,CurrentDate,CurrentMonthToDate,CurrentFullMonthBudget,LastMonthToDate,
			   LastFullMonth,LastFullMonthBudget,FullYearActual,FullYearBudget,FullYearDailyAverage,
			   FullYearMonthlyAverage,FullYearThreeMonthDailyAverage,FullYearThreeMonthAverage 
		FROM #TempResult (NOLOCK)
	end
	
	
	DROP TABLE #TempResult
	DROP TABLE #MTD_TopThreeSports
	DROP TABLE #TopThreeSportsResult
END


GO
GRANT EXECUTE ON [dbo].[KPI_GetTopThreeSports] TO [bodbAdminNet] AS [dbo]
GO
GRANT EXECUTE ON [dbo].[KPI_GetTopThreeSports] TO [bodbLicenseeNet] AS [dbo]
GO
GRANT VIEW DEFINITION ON [dbo].[KPI_GetTopThreeSports] TO [vnteam] AS [dbo]