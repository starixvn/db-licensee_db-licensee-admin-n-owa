USE [bodb_licensee]
GO

/****** Object:  StoredProcedure [dbo].[KPI_GetReportData]    Script Date: 6/2/2014 16:11:38  ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



ALTER PROCEDURE [dbo].[KPI_GetReportData]   
	@ReportType int = 0,
	@ReportDate datetime = NULL
AS  
  
/*  
 * Created by : 20140117@Francis 
 * Task  : Get all data for sportbook/non-sportbook KPI report(exclude BA and SUNCITY) 
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 		-20140213@Francis: Set N/A StatID in Credit Branch to value 0 in sportbook report
		-20140530@Francis: Support Keno product
 			
 * Param's Explanation:    
 * 
 */  
 
BEGIN
	declare 
    @FirstDayOfLastThreeMonths datetime,
    @FirstDayOfYear datetime,
    @FromDate datetime,
    @ToDate datetime,
    @TempID int
  
	if (@ReportDate IS NULL)
		select @ToDate = convert(varchar(10), dateadd(dd, -1, current_timestamp), 120)
	else
		select @ToDate = convert(varchar(10), @ReportDate, 120)
    
	select @FirstDayOfLastThreeMonths = DATEADD(MONTH, DATEDIFF(MONTH, 0, @ToDate) - 3, 0) -- First Day of Last Three Months

	select @FirstDayOfYear = DATEADD(yy, DATEDIFF(yy,0,@ToDate), 0) -- First Day of Year

	if (@FirstDayOfYear > @FirstDayOfLastThreeMonths)
		select @FromDate = @FirstDayOfLastThreeMonths
	else
		select @FromDate = @FirstDayOfYear
		
				
	CREATE TABLE #Temp
	(
		ReportDate datetime,
		StatID int,
		SectionID int,
		GroupID int,
		BranchID int,
		Value float
	)
	
	CREATE TABLE #Result
	(
		ReportDate datetime,
		StatID int,
		SectionID int,
		GroupID int,
		BranchID int,
		Value float
	)
	--Get result
	declare @Sites table(LicenseeID int,SiteID int,SiteName varchar(50),DateStarted smalldatetime)	
	--For SportBook	
	IF @ReportType = 0
	BEGIN
		delete FROM #Temp
		delete FROM #Result
		delete from @Sites
		
		insert into @Sites(LicenseeID,SiteID,SiteName,DateStarted)
	    SELECT lr.LicenseeID, CASE WHEN lbl.licenseeid IS NULL THEN l.licenseeid ELSE lbl.LabelID END AS LabelID, 
               CASE WHEN lbl.licenseeid IS NULL THEN l.LicenseeName ELSE lbl.LabelName END AS LabelName, 
               CASE WHEN lbl.licenseeid IS NULL THEN l.AffectedDate ELSE lbl.AffectedDate END AS AffectedDate
		FROM dbo.LicenseeReseller AS lr WITH (NOLOCK) LEFT OUTER JOIN
             dbo.Licensees AS l WITH (NOLOCK) ON lr.LicenseeID = l.LicenseeID LEFT OUTER JOIN
             dbo.Labels AS lbl WITH (NOLOCK) ON lr.LicenseeID = lbl.LicenseeID LEFT OUTER JOIN
             dbo.SystemLicensee AS syslic WITH (NOLOCK) ON lr.LicenseeID = syslic.LicenseeID
		WHERE (lr.ResellerID NOT IN (6,3)) AND (syslic.SystemID = 5) AND (syslic.IsActive = 1)
	    
	insert INTO #Temp (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		select 
		mtd.rptDate AS [ReportDate],
		mtd.StatID,
		ss.SectionID,
		g.GroupID,
		bg.BranchID,
		isnull(
			sum(
	            case 
		            when mtd.StatID in (14,16) then 0 
					else mtd.MonthToDate 
				end * case when stat.IsCurrency = 1 then EUR else 1 end),0) AS [Value]
		from dbo.rptKPI_MTD_Cross mtd (nolock)
			inner join @Sites sites on mtd.siteid = sites.SiteID
			inner join dbo.KPI_Groups g (NOLOCK) on sites.LicenseeID = g.SiteID
			inner join dbo.KPI_SectionStatistic ss (NOLOCK) ON mtd.StatID = ss.StatID
			inner join dbo.KPI_BranchGroup bg (NOLOCK) ON g.GroupID = bg.GroupID AND bg.ProductID = 0 
			left join dbo.view_kpi_statistics stat on mtd.StatID = stat.StatID
			left join bodb02.dbo.Lrf_f_GetExchangeDaily(@FromDate,@ToDate) oanda on mtd.rptdate = oanda.exchangedate and mtd.currencyid = oanda.exchangeid
		where rptDate between @FromDate and @ToDate
			and (sites.DateStarted is null or rptDate >= sites.DateStarted)
		group by 
			mtd.rptDate,
			mtd.StatID,
			ss.SectionID,
			g.GroupID,
			bg.BranchID
		order by bg.BranchID, g.GroupID
	
	insert INTO #Result (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT ReportDate,StatID,SectionID,GroupID,BranchID,Value
		FROM #Temp (NOLOCK)
	
	--remove recalculated StatID to add it later
	delete FROM #Result where StatID = 15
	
	--insert additional Statistics
	insert INTO #Result (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT t1.ReportDate,8 AS StatID,t1.SectionID,t1.GroupID,t1.BranchID,
		CASE 
			WHEN t1.Value = 0 THEN 0
			else (t2.Value/t1.Value) END
		AS AverageBetSize
		FROM #Temp (NOLOCK) t1 inner join #Temp (NOLOCK) t2 
		ON t1.ReportDate = t2.ReportDate and t1.SectionID = t2.SectionID and t1.GroupID = t2.GroupID and t1.BranchID = t2.BranchID
		WHERE t1.StatID = 7 and t2.StatID = 9
		union all
		SELECT t1.ReportDate,18 AS StatID,t1.SectionID,t1.GroupID,t1.BranchID,
		CASE 
			WHEN t1.Value = 0 THEN 0
			else (t2.Value/t1.Value) END
		AS AverageBetSizeNoDraw
		FROM #Temp (NOLOCK) t1 inner join #Temp (NOLOCK) t2 
		ON t1.ReportDate = t2.ReportDate and t1.SectionID = t2.SectionID and t1.GroupID = t2.GroupID and t1.BranchID = t2.BranchID
		WHERE t1.StatID = 17 and t2.StatID = 19
		union all
		SELECT t1.ReportDate,1000 AS StatID,t1.SectionID,t1.GroupID,t1.BranchID,((t1.Value+t2.Value)*-1) AS ToTalNetWin
		FROM #Temp (NOLOCK) t1 inner join #Temp (NOLOCK) t2 
		ON t1.ReportDate = t2.ReportDate and t1.SectionID = t2.SectionID and t1.GroupID = t2.GroupID and t1.BranchID = t2.BranchID
		WHERE t1.StatID = 10 and t2.StatID = 11
		union all
		SELECT t1.ReportDate,1001 AS StatID,t1.SectionID,t1.GroupID,t1.BranchID,
		CASE 
			WHEN t3.Value = 0 THEN 0
			else (-1*(t1.Value+t2.Value)/t3.Value) END	
		AS Margin
		FROM #Temp (NOLOCK) t1 inner join #Temp (NOLOCK) t2 
		ON t1.ReportDate = t2.ReportDate and t1.SectionID = t2.SectionID and t1.GroupID = t2.GroupID and t1.BranchID = t2.BranchID
		inner JOIN #Temp (NOLOCK) t3
		ON t1.ReportDate = t3.ReportDate and t1.SectionID = t3.SectionID and t1.GroupID = t3.GroupID and t1.BranchID = t3.BranchID
		WHERE t1.StatID = 10 and t2.StatID = 11 AND t3.StatID = 19
		
	--insert additional financials statistics		
	insert INTO #Result (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT t1.ReportDate,15 AS StatID,5,t1.GroupID,t1.BranchID,(t1.Value*0.15) AS SportRevenueNetWin
		FROM #Result (NOLOCK) t1 
		WHERE t1.StatID = 1000
	
	insert INTO #Result (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT t1.ReportDate,1100 AS StatID,5,t1.GroupID,t1.BranchID,t1.Value AS SportRevenueToTalInEUR
		FROM #Result (NOLOCK) t1 
		WHERE t1.StatID = 15
		
	insert INTO #Result (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT t1.ReportDate,1400 AS StatID,5,t1.GroupID,t1.BranchID,(t1.Value * oanda.MYR) AS SportRevenueToTalInMYR
		FROM #Result (NOLOCK) t1
		left join bodb02.dbo.Lrf_f_GetExchangeDaily(@FromDate,@ToDate) oanda on t1.ReportDate = oanda.exchangedate and oanda.exchangeid = 6
		WHERE t1.StatID = 1100

	--Set N/A StatID in Credit Branch to value 0 in sportbook report
	
	UPDATE #Result WITH (UPDLOCK, ROWLOCK)
		SET Value = 0
		WHERE StatID NOT IN (7,17)
		AND BranchID = 4	
	end
	
	
	--For Non-Sportbook
	IF @ReportType = 1
	
	BEGIN
		
	--For NG
		CREATE TABLE #TempResult
		(
			ReportDate datetime,
			StatID int,
			SectionID int,
			GroupID int,
			BranchID int,
			Value float
		)
	
		delete FROM #Temp
		delete FROM #TempResult
		delete FROM #Result
		delete from @Sites
		
		insert into @Sites (LicenseeID,SiteID,SiteName,DateStarted)
		SELECT lr.LicenseeID, CASE WHEN lbl.licenseeid IS NULL THEN l.licenseeid ELSE lbl.LabelID END AS LabelID, 
               CASE WHEN lbl.licenseeid IS NULL THEN l.LicenseeName ELSE lbl.LabelName END AS LabelName,  
               CASE WHEN lbl.licenseeid IS NULL THEN l.AffectedDate ELSE lbl.AffectedDate END AS AffectedDate
		FROM dbo.LicenseeProduct3rd AS lp WITH (NOLOCK) INNER JOIN
             dbo.LicenseeReseller AS lr WITH (NOLOCK) ON lp.LicenseeID = lr.LicenseeID LEFT OUTER JOIN
             dbo.Licensees AS l WITH (NOLOCK) ON lr.LicenseeID = l.LicenseeID LEFT OUTER JOIN
             dbo.Labels AS lbl WITH (NOLOCK) ON lr.LicenseeID = lbl.LicenseeID LEFT OUTER JOIN
             dbo.SystemLicensee AS syslic WITH (NOLOCK) ON lr.LicenseeID = syslic.LicenseeID
		WHERE (lr.ResellerID NOT IN (6,3)) AND (lp.ProductID = 2) AND (syslic.SystemID = 5) AND (syslic.IsActive = 1)
	    
	    UPDATE 	@Sites
		SET  DateStarted =
				CASE WHEN LicenseeID = 13 THEN '2012-04-01'
					 WHEN LicenseeID = 18 THEN '2012-03-02'
					 WHEN SiteID = 1 THEN '2012-05-01'
					 ELSE '2012-09-19'
				END
	    
		INSERT INTO #Temp(ReportDate,StatID,SectionID,GroupID,BranchID,[Value])
		select 
		mtd.rptDate AS [Date],
		mtd.StatID,
		ss.SectionID,
		g.GroupID,
		bg.BranchID,
		isnull(
			sum(
	            case 
		            when mtd.StatID in (14,16) then 0 
					else mtd.MonthToDate 
				end * case when stat.IsCurrency = 1 then EUR else 1 end),0) AS [Value] 
		from dbo.rptKPI_MTD_3rdProducts mtd (nolock)
			inner join @Sites sites on mtd.siteid = sites.SiteID
			inner join dbo.KPI_Groups g (NOLOCK) on sites.LicenseeID = g.SiteID
			inner join dbo.KPI_SectionStatistic ss (NOLOCK) ON mtd.StatID = ss.StatID
			inner join dbo.KPI_BranchGroup bg (NOLOCK) ON g.GroupID = bg.GroupID AND bg.ProductID = 2 
			left join dbo.view_kpi_statistics stat on mtd.StatID = stat.StatID
			left join bodb02.dbo.Lrf_f_GetExchangeDaily(@FromDate,@ToDate) oanda on mtd.rptdate = oanda.exchangedate and mtd.currencyid = oanda.exchangeid
		where rptDate between @FromDate and @ToDate
			and (sites.DateStarted is null or rptDate >= sites.DateStarted)
			and mtd.bettype between 81 AND 120
		group by 
			mtd.rptDate,
			mtd.StatID,
			ss.SectionID,
			g.GroupID,
			bg.BranchID
		order by bg.BranchID, g.GroupID	 
		
		insert INTO #TempResult (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT ReportDate,StatID,SectionID,GroupID,BranchID,Value
		FROM #Temp (NOLOCK)
	
	--remove recalculated StatID to add it later
		delete FROM #TempResult where StatID = 15
	
	--insert additional Statistics
		insert INTO #TempResult (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT t1.ReportDate,8 AS StatID,t1.SectionID,t1.GroupID,t1.BranchID,
		CASE 
			WHEN t1.Value = 0 THEN 0
			else (t2.Value/t1.Value) END
		AS AverageBetSize
		FROM #Temp (NOLOCK) t1 inner join #Temp (NOLOCK) t2 
		ON t1.ReportDate = t2.ReportDate and t1.SectionID = t2.SectionID and t1.GroupID = t2.GroupID and t1.BranchID = t2.BranchID
		WHERE t1.StatID = 7 and t2.StatID = 9
		union all
		SELECT t1.ReportDate,18 AS StatID,t1.SectionID,t1.GroupID,t1.BranchID,
		CASE 
			WHEN t1.Value = 0 THEN 0
			else (t2.Value/t1.Value) END
		AS AverageBetSizeNoDraw
		FROM #Temp (NOLOCK) t1 inner join #Temp (NOLOCK) t2 
		ON t1.ReportDate = t2.ReportDate and t1.SectionID = t2.SectionID and t1.GroupID = t2.GroupID and t1.BranchID = t2.BranchID
		WHERE t1.StatID = 17 and t2.StatID = 19
		union all
		SELECT t1.ReportDate,1000 AS StatID,t1.SectionID,t1.GroupID,t1.BranchID,((t1.Value+t2.Value)*-1) AS ToTalNetWin
		FROM #Temp (NOLOCK) t1 inner join #Temp (NOLOCK) t2 
		ON t1.ReportDate = t2.ReportDate and t1.SectionID = t2.SectionID and t1.GroupID = t2.GroupID and t1.BranchID = t2.BranchID
		WHERE t1.StatID = 10 and t2.StatID = 11
		union all
		SELECT t1.ReportDate,1001 AS StatID,t1.SectionID,t1.GroupID,t1.BranchID,
		CASE 
			WHEN t3.Value = 0 THEN 0
			else (-1*(t1.Value+t2.Value)/t3.Value) END	
		AS Margin
		FROM #Temp (NOLOCK) t1 inner join #Temp (NOLOCK) t2 
		ON t1.ReportDate = t2.ReportDate and t1.SectionID = t2.SectionID and t1.GroupID = t2.GroupID and t1.BranchID = t2.BranchID
		inner JOIN #Temp (NOLOCK) t3
		ON t1.ReportDate = t3.ReportDate and t1.SectionID = t3.SectionID and t1.GroupID = t3.GroupID and t1.BranchID = t3.BranchID
		WHERE t1.StatID = 10 and t2.StatID = 11 AND t3.StatID = 19
		
	--insert additional financials statistics		
	--Hard-code for HAIFA
		select @TempID = GroupID
		FROM KPI_Groups (NOLOCK)
		where GroupName = 'HAIFA'
	
		insert INTO #TempResult (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT t1.ReportDate,15 AS StatID,5,t1.GroupID,t1.BranchID,
		CASE WHEN t1.GroupID = @TempID
			 THEN t1.Value * 0.075
			 else t1.Value * 0.15
			 END AS SportRevenueGrossWin
		FROM #TempResult (NOLOCK) t1 inner JOIN KPI_Groups g (NOLOCK)
			ON t1.GroupID = g.GroupID inner JOIN bodb_licensee.dbo.Licensees (NOLOCK) l
			ON g.SiteID = l.LicenseeID
		WHERE t1.StatID = 1000 AND l.isDeposit = 1
		
		insert INTO #TempResult (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT t1.ReportDate,15 AS StatID,5,t1.GroupID,t1.BranchID,
		(t1.Value * 0.05) AS SportRevenueGrossWin
		FROM #TempResult (NOLOCK) t1 inner JOIN KPI_Groups g (NOLOCK)
			ON t1.GroupID = g.GroupID inner JOIN bodb_licensee.dbo.Licensees (NOLOCK) l
			ON g.SiteID = l.LicenseeID
		WHERE t1.StatID = 1000 AND l.isDeposit = 0
	
		insert INTO #TempResult (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT t1.ReportDate,1100 AS StatID,5,t1.GroupID,t1.BranchID,t1.Value AS SportRevenueToTalInEUR
		FROM #TempResult (NOLOCK) t1 
		WHERE t1.StatID = 15
		
		insert INTO #TempResult (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT t1.ReportDate,1400 AS StatID,5,t1.GroupID,t1.BranchID,(t1.Value * oanda.MYR) AS SportRevenueToTalInMYR
		FROM #TempResult (NOLOCK) t1
		left join bodb02.dbo.Lrf_f_GetExchangeDaily(@FromDate,@ToDate) oanda on t1.ReportDate = oanda.exchangedate and oanda.exchangeid = 6
		WHERE t1.StatID = 1100
		
		insert INTO #Result(ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT ReportDate,StatID,SectionID,GroupID,BranchID,Value
		FROM #TempResult (NOLOCK)

		
		--For LC
		delete FROM #Temp
		delete FROM #TempResult
		delete from @Sites
		
		insert into @Sites (LicenseeID,SiteID,SiteName,DateStarted)
		SELECT lr.LicenseeID, CASE WHEN lbl.licenseeid IS NULL THEN l.licenseeid ELSE lbl.LabelID END AS LabelID, 
               CASE WHEN lbl.licenseeid IS NULL THEN l.LicenseeName ELSE lbl.LabelName END AS LabelName,  
               CASE WHEN lbl.licenseeid IS NULL THEN l.AffectedDate ELSE lbl.AffectedDate END AS AffectedDate
		FROM dbo.LicenseeProduct3rd AS lp WITH (NOLOCK) INNER JOIN
             dbo.LicenseeReseller AS lr WITH (NOLOCK) ON lp.LicenseeID = lr.LicenseeID LEFT OUTER JOIN
             dbo.Licensees AS l WITH (NOLOCK) ON lr.LicenseeID = l.LicenseeID LEFT OUTER JOIN
             dbo.Labels AS lbl WITH (NOLOCK) ON lr.LicenseeID = lbl.LicenseeID LEFT OUTER JOIN
             dbo.SystemLicensee AS syslic WITH (NOLOCK) ON lr.LicenseeID = syslic.LicenseeID
		WHERE  (lr.ResellerID NOT IN (6,3)) AND (lp.ProductID = 4) AND (syslic.SystemID = 5) AND (syslic.IsActive = 1)
	    
	    UPDATE @Sites
		SET DateStarted = '2012-11-01'
						
	    
		INSERT INTO #Temp(ReportDate,StatID,SectionID,GroupID,BranchID,[Value])
		select 
		mtd.rptDate AS [Date],
		mtd.StatID,
		ss.SectionID,
		g.GroupID,
		bg.BranchID,
		isnull(
			sum(
	            case 
		            when mtd.StatID in (14,16) then 0 
					else mtd.MonthToDate 
				end * case when stat.IsCurrency = 1 then EUR else 1 end),0) AS [Value] 
		from dbo.rptKPI_MTD_3rdProducts mtd (nolock)
			inner join @Sites sites on mtd.siteid = sites.SiteID
			inner join dbo.KPI_Groups g (NOLOCK) on sites.LicenseeID = g.SiteID
			inner join dbo.KPI_SectionStatistic ss (NOLOCK) ON mtd.StatID = ss.StatID
			inner join dbo.KPI_BranchGroup bg (NOLOCK) ON g.GroupID = bg.GroupID AND bg.ProductID = 4 
			left join dbo.view_kpi_statistics stat on mtd.StatID = stat.StatID
			left join bodb02.dbo.Lrf_f_GetExchangeDaily(@FromDate,@ToDate) oanda on mtd.rptdate = oanda.exchangedate and mtd.currencyid = oanda.exchangeid
		where rptDate between @FromDate and @ToDate
			and (sites.DateStarted is null or rptDate >= sites.DateStarted)
			and mtd.bettype between 1101 AND 1199
		group by 
			mtd.rptDate,
			mtd.StatID,
			ss.SectionID,
			g.GroupID,
			bg.BranchID
		order by bg.BranchID, g.GroupID
			
		insert INTO #TempResult (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
			SELECT ReportDate,StatID,SectionID,GroupID,BranchID,Value
			FROM #Temp (NOLOCK)
	
	--remove recalculated StatID to add it later
		delete FROM #TempResult where StatID = 15
	
	--insert additional Statistics
		insert INTO #TempResult (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT t1.ReportDate,8 AS StatID,t1.SectionID,t1.GroupID,t1.BranchID,
		CASE 
			WHEN t1.Value = 0 THEN 0
			else (t2.Value/t1.Value) END
		AS AverageBetSize
		FROM #Temp (NOLOCK) t1 inner join #Temp (NOLOCK) t2 
		ON t1.ReportDate = t2.ReportDate and t1.SectionID = t2.SectionID and t1.GroupID = t2.GroupID and t1.BranchID = t2.BranchID
		WHERE t1.StatID = 7 and t2.StatID = 9
		union all
		SELECT t1.ReportDate,18 AS StatID,t1.SectionID,t1.GroupID,t1.BranchID,
		CASE 
			WHEN t1.Value = 0 THEN 0
			else (t2.Value/t1.Value) END
		AS AverageBetSizeNoDraw
		FROM #Temp (NOLOCK) t1 inner join #Temp (NOLOCK) t2 
		ON t1.ReportDate = t2.ReportDate and t1.SectionID = t2.SectionID and t1.GroupID = t2.GroupID and t1.BranchID = t2.BranchID
		WHERE t1.StatID = 17 and t2.StatID = 19
		union all
		SELECT t1.ReportDate,1000 AS StatID,t1.SectionID,t1.GroupID,t1.BranchID,((t1.Value+t2.Value)*-1) AS ToTalNetWin
		FROM #Temp (NOLOCK) t1 inner join #Temp (NOLOCK) t2 
		ON t1.ReportDate = t2.ReportDate and t1.SectionID = t2.SectionID and t1.GroupID = t2.GroupID and t1.BranchID = t2.BranchID
		WHERE t1.StatID = 10 and t2.StatID = 11
		union all
		SELECT t1.ReportDate,1001 AS StatID,t1.SectionID,t1.GroupID,t1.BranchID,
		CASE 
			WHEN t3.Value = 0 THEN 0
			else (-1*(t1.Value+t2.Value)/t3.Value) END
		AS Margin
		FROM #Temp (NOLOCK) t1 inner join #Temp (NOLOCK) t2 
		ON t1.ReportDate = t2.ReportDate and t1.SectionID = t2.SectionID and t1.GroupID = t2.GroupID and t1.BranchID = t2.BranchID
		inner JOIN #Temp (NOLOCK) t3
		ON t1.ReportDate = t3.ReportDate and t1.SectionID = t3.SectionID and t1.GroupID = t3.GroupID and t1.BranchID = t3.BranchID
		WHERE t1.StatID = 10 and t2.StatID = 11 AND t3.StatID = 19
		
		--insert additional financials statistics		
	
		insert INTO #TempResult (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT t1.ReportDate,15 AS StatID,5,t1.GroupID,t1.BranchID,
		(t1.Value * 0.07) AS SportRevenueGrossWin
		FROM #TempResult (NOLOCK) t1 inner JOIN KPI_Groups g (NOLOCK)
			ON t1.GroupID = g.GroupID inner JOIN bodb_licensee.dbo.Licensees (NOLOCK) l
			ON g.SiteID = l.LicenseeID
		WHERE t1.StatID = 1000 AND l.isDeposit = 1
		
		insert INTO #TempResult (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT t1.ReportDate,15 AS StatID,5,t1.GroupID,t1.BranchID,
		(t1.Value * 0.015) AS SportRevenueGrossWin
		FROM #TempResult (NOLOCK) t1 inner JOIN KPI_Groups g (NOLOCK)
			ON t1.GroupID = g.GroupID inner JOIN bodb_licensee.dbo.Licensees (NOLOCK) l
			ON g.SiteID = l.LicenseeID
		WHERE t1.StatID = 1000 AND l.isDeposit = 0
	
		insert INTO #TempResult (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT t1.ReportDate,1100 AS StatID,5,t1.GroupID,t1.BranchID,t1.Value AS SportRevenueToTalInEUR
		FROM #TempResult (NOLOCK) t1 
		WHERE t1.StatID = 15
		
		insert INTO #TempResult (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT t1.ReportDate,1400 AS StatID,5,t1.GroupID,t1.BranchID,(t1.Value * oanda.MYR) AS SportRevenueToTalInMYR
		FROM #TempResult (NOLOCK) t1
		left join bodb02.dbo.Lrf_f_GetExchangeDaily(@FromDate,@ToDate) oanda on t1.ReportDate = oanda.exchangedate and oanda.exchangeid = 6
		WHERE t1.StatID = 1100
		
		insert INTO #Result(ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT ReportDate,StatID,SectionID,GroupID,BranchID,Value
		FROM #TempResult (NOLOCK)
		
		--For Keno
		delete FROM #Temp
		delete FROM #TempResult
		delete from @Sites
		
		insert into @Sites (LicenseeID,SiteID,SiteName,DateStarted)
		SELECT lr.LicenseeID, CASE WHEN lbl.licenseeid IS NULL THEN l.licenseeid ELSE lbl.LabelID END AS LabelID, 
               CASE WHEN lbl.licenseeid IS NULL THEN l.LicenseeName ELSE lbl.LabelName END AS LabelName,  
               CASE WHEN lbl.licenseeid IS NULL THEN l.AffectedDate ELSE lbl.AffectedDate END AS AffectedDate
		FROM dbo.LicenseeProduct3rd AS lp WITH (NOLOCK) INNER JOIN
             dbo.LicenseeReseller AS lr WITH (NOLOCK) ON lp.LicenseeID = lr.LicenseeID LEFT OUTER JOIN
             dbo.Licensees AS l WITH (NOLOCK) ON lr.LicenseeID = l.LicenseeID LEFT OUTER JOIN
             dbo.Labels AS lbl WITH (NOLOCK) ON lr.LicenseeID = lbl.LicenseeID LEFT OUTER JOIN
             dbo.SystemLicensee AS syslic WITH (NOLOCK) ON lr.LicenseeID = syslic.LicenseeID
		WHERE  (lr.ResellerID NOT IN (6,3)) AND (lp.ProductID = 8) AND (syslic.SystemID = 5) AND (syslic.IsActive = 1)
	    	    			
		INSERT INTO #Temp(ReportDate,StatID,SectionID,GroupID,BranchID,[Value])
		select 
		mtd.rptDate AS [Date],
		mtd.StatID,
		ss.SectionID,
		g.GroupID,
		bg.BranchID,
		isnull(
			sum(
	            case 
		            when mtd.StatID in (14,16) then 0 
					else mtd.MonthToDate 
				end * case when stat.IsCurrency = 1 then EUR else 1 end),0) AS [Value] 
		from dbo.rptKPI_MTD_3rdProducts mtd (nolock)
			inner join @Sites sites on mtd.siteid = sites.SiteID
			inner join dbo.KPI_Groups g (NOLOCK) on sites.LicenseeID = g.SiteID
			inner join dbo.KPI_SectionStatistic ss (NOLOCK) ON mtd.StatID = ss.StatID
			inner join dbo.KPI_BranchGroup bg (NOLOCK) ON g.GroupID = bg.GroupID AND bg.ProductID = 8 
			left join dbo.view_kpi_statistics stat on mtd.StatID = stat.StatID
			left join bodb02.dbo.Lrf_f_GetExchangeDaily(@FromDate,@ToDate) oanda on mtd.rptdate = oanda.exchangedate and mtd.currencyid = oanda.exchangeid
		where rptDate between @FromDate and @ToDate
			and (sites.DateStarted is null or rptDate >= sites.DateStarted)
			and mtd.bettype between 1501 and 1599
		group by 
			mtd.rptDate,
			mtd.StatID,
			ss.SectionID,
			g.GroupID,
			bg.BranchID
		order by bg.BranchID, g.GroupID
			
		insert INTO #TempResult (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
			SELECT ReportDate,StatID,SectionID,GroupID,BranchID,Value
			FROM #Temp (NOLOCK)
	
	--remove recalculated StatID to add it later
		delete FROM #TempResult where StatID = 15
	
	--insert additional Statistics
		insert INTO #TempResult (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT t1.ReportDate,8 AS StatID,t1.SectionID,t1.GroupID,t1.BranchID,
		CASE 
			WHEN t1.Value = 0 THEN 0
			else (t2.Value/t1.Value) END
		AS AverageBetSize
		FROM #Temp (NOLOCK) t1 inner join #Temp (NOLOCK) t2 
		ON t1.ReportDate = t2.ReportDate and t1.SectionID = t2.SectionID and t1.GroupID = t2.GroupID and t1.BranchID = t2.BranchID
		WHERE t1.StatID = 7 and t2.StatID = 9
		union all
		SELECT t1.ReportDate,18 AS StatID,t1.SectionID,t1.GroupID,t1.BranchID,
		CASE 
			WHEN t1.Value = 0 THEN 0
			else (t2.Value/t1.Value) END
		AS AverageBetSizeNoDraw
		FROM #Temp (NOLOCK) t1 inner join #Temp (NOLOCK) t2 
		ON t1.ReportDate = t2.ReportDate and t1.SectionID = t2.SectionID and t1.GroupID = t2.GroupID and t1.BranchID = t2.BranchID
		WHERE t1.StatID = 17 and t2.StatID = 19
		union all
		SELECT t1.ReportDate,1000 AS StatID,t1.SectionID,t1.GroupID,t1.BranchID,((t1.Value+t2.Value)*-1) AS ToTalNetWin
		FROM #Temp (NOLOCK) t1 inner join #Temp (NOLOCK) t2 
		ON t1.ReportDate = t2.ReportDate and t1.SectionID = t2.SectionID and t1.GroupID = t2.GroupID and t1.BranchID = t2.BranchID
		WHERE t1.StatID = 10 and t2.StatID = 11
		union all
		SELECT t1.ReportDate,1001 AS StatID,t1.SectionID,t1.GroupID,t1.BranchID,
		CASE 
			WHEN t3.Value = 0 THEN 0
			else (-1*(t1.Value+t2.Value)/t3.Value) END
		AS Margin
		FROM #Temp (NOLOCK) t1 inner join #Temp (NOLOCK) t2 
		ON t1.ReportDate = t2.ReportDate and t1.SectionID = t2.SectionID and t1.GroupID = t2.GroupID and t1.BranchID = t2.BranchID
		inner JOIN #Temp (NOLOCK) t3
		ON t1.ReportDate = t3.ReportDate and t1.SectionID = t3.SectionID and t1.GroupID = t3.GroupID and t1.BranchID = t3.BranchID
		WHERE t1.StatID = 10 and t2.StatID = 11 AND t3.StatID = 19
		
		--insert additional financials statistics		
		insert INTO #TempResult (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT t1.ReportDate,15 AS StatID,5,t1.GroupID,t1.BranchID,
		(t1.Value * 0.15) AS SportRevenueGrossWin
		FROM #TempResult (NOLOCK) t1 inner JOIN KPI_Groups g (NOLOCK)
			ON t1.GroupID = g.GroupID inner JOIN bodb_licensee.dbo.Licensees (NOLOCK) l
			ON g.SiteID = l.LicenseeID
		WHERE t1.StatID = 1000 AND l.isDeposit = 1
		
		insert INTO #TempResult (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT t1.ReportDate,15 AS StatID,5,t1.GroupID,t1.BranchID,
		(t1.Value * 0) AS SportRevenueGrossWin
		FROM #TempResult (NOLOCK) t1 inner JOIN KPI_Groups g (NOLOCK)
			ON t1.GroupID = g.GroupID inner JOIN bodb_licensee.dbo.Licensees (NOLOCK) l
			ON g.SiteID = l.LicenseeID
		WHERE t1.StatID = 1000 AND l.isDeposit = 0
	
		insert INTO #TempResult (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT t1.ReportDate,1100 AS StatID,5,t1.GroupID,t1.BranchID,t1.Value AS SportRevenueToTalInEUR
		FROM #TempResult (NOLOCK) t1 
		WHERE t1.StatID = 15
		
		insert INTO #TempResult (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT t1.ReportDate,1400 AS StatID,5,t1.GroupID,t1.BranchID,(t1.Value * oanda.MYR) AS SportRevenueToTalInMYR
		FROM #TempResult (NOLOCK) t1
		left join bodb02.dbo.Lrf_f_GetExchangeDaily(@FromDate,@ToDate) oanda on t1.ReportDate = oanda.exchangedate and oanda.exchangeid = 6
		WHERE t1.StatID = 1100
		
		insert INTO #Result(ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT ReportDate,StatID,SectionID,GroupID,BranchID,Value
		FROM #TempResult (NOLOCK)

		--For VS
		delete FROM #Temp
		delete FROM #TempResult
		delete from @Sites
		
		insert into @Sites (LicenseeID,SiteID,SiteName,DateStarted)
		SELECT lr.LicenseeID, CASE WHEN lbl.licenseeid IS NULL THEN l.licenseeid ELSE lbl.LabelID END AS LabelID, 
               CASE WHEN lbl.licenseeid IS NULL THEN l.LicenseeName ELSE lbl.LabelName END AS LabelName,  
               CASE WHEN lbl.licenseeid IS NULL THEN l.AffectedDate ELSE lbl.AffectedDate END AS AffectedDate
		FROM dbo.LicenseeProduct3rd AS lp WITH (NOLOCK) INNER JOIN
             dbo.LicenseeReseller AS lr WITH (NOLOCK) ON lp.LicenseeID = lr.LicenseeID LEFT OUTER JOIN
             dbo.Licensees AS l WITH (NOLOCK) ON lr.LicenseeID = l.LicenseeID LEFT OUTER JOIN
             dbo.Labels AS lbl WITH (NOLOCK) ON lr.LicenseeID = lbl.LicenseeID LEFT OUTER JOIN
             dbo.SystemLicensee AS syslic WITH (NOLOCK) ON lr.LicenseeID = syslic.LicenseeID
		WHERE  (lr.ResellerID NOT IN (6,3)) AND (lp.ProductID = 5) AND (syslic.SystemID = 5) AND (syslic.IsActive = 1)
	    
	    UPDATE @Sites
		SET DateStarted = '2012-11-01'
						
	    INSERT INTO #Temp (ReportDate,StatID,SectionID,GroupID,BranchID,[Value])
		select 
		mtd.rptDate AS [Date],
		mtd.StatID,
		ss.SectionID,
		g.GroupID,
		bg.BranchID,
		isnull(
			sum(
	            case 
		            when mtd.StatID in (14,16) then 0 
					else mtd.MonthToDate 
				end * case when stat.IsCurrency = 1 then EUR else 1 end),0) AS [Value] 
		from dbo.rptKPI_MTD_3rdProducts mtd (nolock)
			inner join @Sites sites on mtd.siteid = sites.SiteID
			inner join dbo.KPI_Groups g (NOLOCK) on sites.LicenseeID = g.SiteID
			inner join dbo.KPI_SectionStatistic ss (NOLOCK) ON mtd.StatID = ss.StatID
			inner join dbo.KPI_BranchGroup bg (NOLOCK) ON g.GroupID = bg.GroupID AND bg.ProductID = 5 
			left join dbo.view_kpi_statistics stat on mtd.StatID = stat.StatID
			left join bodb02.dbo.Lrf_f_GetExchangeDaily(@FromDate,@ToDate) oanda on mtd.rptdate = oanda.exchangedate and mtd.currencyid = oanda.exchangeid
		where rptDate between @FromDate and @ToDate
			and (sites.DateStarted is null or rptDate >= sites.DateStarted)
			and mtd.bettype between 1201 AND 1299
		group by 
			mtd.rptDate,
			mtd.StatID,
			ss.SectionID,
			g.GroupID,
			bg.BranchID
		order by bg.BranchID, g.GroupID
		
		
		insert INTO #TempResult (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
			SELECT ReportDate,StatID,SectionID,GroupID,BranchID,Value
			FROM #Temp (NOLOCK)
	
	--remove recalculated StatID to add it later
		delete FROM #TempResult where StatID = 15
	
	--insert additional Statistics
		insert INTO #TempResult (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT t1.ReportDate,8 AS StatID,t1.SectionID,t1.GroupID,t1.BranchID,
		CASE 
			WHEN t1.Value = 0 THEN 0
			else (t2.Value/t1.Value) END
		AS AverageBetSize
		FROM #Temp (NOLOCK) t1 inner join #Temp (NOLOCK) t2 
		ON t1.ReportDate = t2.ReportDate and t1.SectionID = t2.SectionID and t1.GroupID = t2.GroupID and t1.BranchID = t2.BranchID
		WHERE t1.StatID = 7 and t2.StatID = 9
		union all
		SELECT t1.ReportDate,18 AS StatID,t1.SectionID,t1.GroupID,t1.BranchID,
		CASE 
			WHEN t1.Value = 0 THEN 0
			else (t2.Value/t1.Value) END
		AS AverageBetSizeNoDraw
		FROM #Temp (NOLOCK) t1 inner join #Temp (NOLOCK) t2 
		ON t1.ReportDate = t2.ReportDate and t1.SectionID = t2.SectionID and t1.GroupID = t2.GroupID and t1.BranchID = t2.BranchID
		WHERE t1.StatID = 17 and t2.StatID = 19
		union all
		SELECT t1.ReportDate,1000 AS StatID,t1.SectionID,t1.GroupID,t1.BranchID,((t1.Value+t2.Value)*-1) AS ToTalNetWin
		FROM #Temp (NOLOCK) t1 inner join #Temp (NOLOCK) t2 
		ON t1.ReportDate = t2.ReportDate and t1.SectionID = t2.SectionID and t1.GroupID = t2.GroupID and t1.BranchID = t2.BranchID
		WHERE t1.StatID = 10 and t2.StatID = 11
		union all
		SELECT t1.ReportDate,1001 AS StatID,t1.SectionID,t1.GroupID,t1.BranchID,
		CASE 
			WHEN t3.Value = 0 THEN 0
			else (-1*(t1.Value+t2.Value)/t3.Value) END
		AS Margin
		FROM #Temp (NOLOCK) t1 inner join #Temp (NOLOCK) t2 
		ON t1.ReportDate = t2.ReportDate and t1.SectionID = t2.SectionID and t1.GroupID = t2.GroupID and t1.BranchID = t2.BranchID
		inner JOIN #Temp (NOLOCK) t3
		ON t1.ReportDate = t3.ReportDate and t1.SectionID = t3.SectionID and t1.GroupID = t3.GroupID and t1.BranchID = t3.BranchID
		WHERE t1.StatID = 10 and t2.StatID = 11 AND t3.StatID = 19
		
		--insert additional financials statistics		
	
		insert INTO #TempResult (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT t1.ReportDate,15 AS StatID,5,t1.GroupID,t1.BranchID,
		(t1.Value * 0.15) AS SportRevenueGrossWin
		FROM #TempResult (NOLOCK) t1 inner JOIN KPI_Groups g (NOLOCK)
			ON t1.GroupID = g.GroupID inner JOIN bodb_licensee.dbo.Licensees (NOLOCK) l
			ON g.SiteID = l.LicenseeID
		WHERE t1.StatID = 1000 AND l.isDeposit = 1
		
		insert INTO #TempResult (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT t1.ReportDate,15 AS StatID,5,t1.GroupID,t1.BranchID,
		(t1.Value * 0.02) AS SportRevenueGrossWin
		FROM #TempResult (NOLOCK) t1 inner JOIN KPI_Groups g (NOLOCK)
		ON t1.GroupID = g.GroupID inner JOIN bodb_licensee.dbo.Licensees (NOLOCK) l
			ON g.SiteID = l.LicenseeID
		WHERE t1.StatID = 1000 AND l.isDeposit = 0
	
		insert INTO #TempResult (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT t1.ReportDate,1100 AS StatID,5,t1.GroupID,t1.BranchID,t1.Value AS SportRevenueToTalInEUR
		FROM #TempResult (NOLOCK) t1 
		WHERE t1.StatID = 15
		
		insert INTO #TempResult (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT t1.ReportDate,1400 AS StatID,5,t1.GroupID,t1.BranchID,(t1.Value * oanda.MYR) AS SportRevenueToTalInMYR
		FROM #TempResult (NOLOCK) t1
		left join bodb02.dbo.Lrf_f_GetExchangeDaily(@FromDate,@ToDate) oanda on t1.ReportDate = oanda.exchangedate and oanda.exchangeid = 6
		WHERE t1.StatID = 1100
		
		insert INTO #Result(ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT ReportDate,StatID,SectionID,GroupID,BranchID,Value
		FROM #TempResult (NOLOCK)		

		DROP TABLE #TempResult

	END
	
	select ReportDate,StatID,SectionID,GroupID,BranchID,Value
	from #Result (NOLOCK)
	order by ReportDate, BranchID, GroupID

	DROP TABLE #Temp
	DROP TABLE #Result
	
END






GO


