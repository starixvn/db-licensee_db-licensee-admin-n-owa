USE [bodb_licensee]
GO
ALTER PROCEDURE [dbo].[KPI_GetReportData_BA]   
	@ReportType int = 0,
	@ReportDate datetime = NULL
AS  
  
/*  
 * Created by : 20140122@Francis 
 * Task  : Get all data for BA (branch) KPI report
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
   -20160116@Francis: Change to use KPI_Statistics table instead of view_kpi_statistics
   -20160726@Francis: Move SP to bodb_LicenseeReport - [Redmine: #60449]
 * Param's Explanation:    
 * 
 */  
 
BEGIN
	declare 
	@TempID int,
    @FirstDayOfLastThreeMonths datetime,
    @FirstDayOfYear datetime,
    @FromDate datetime,
    @ToDate datetime
  
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
	
	
	insert into @Sites(LicenseeID,SiteID,SiteName,DateStarted)
		SELECT lr.LicenseeID, CASE WHEN lbl.licenseeid IS NULL THEN l.licenseeid ELSE lbl.LabelID END AS LabelID, 
			CASE WHEN lbl.licenseeid IS NULL THEN l.LicenseeName ELSE lbl.LabelName END AS LabelName, 
			CASE WHEN lbl.licenseeid IS NULL THEN l.AffectedDate ELSE lbl.AffectedDate END AS AffectedDate
		FROM dbo.LicenseeReseller AS lr WITH (NOLOCK) LEFT OUTER JOIN
	        dbo.Licensees AS l WITH (NOLOCK) ON lr.LicenseeID = l.LicenseeID LEFT OUTER JOIN
			dbo.Labels AS lbl WITH (NOLOCK) ON lr.LicenseeID = lbl.LicenseeID LEFT OUTER JOIN
			dbo.SystemLicensee AS syslic WITH (NOLOCK) ON lr.LicenseeID = syslic.LicenseeID
		WHERE (lr.ResellerID = 3) AND (syslic.SystemID = 5) AND (syslic.IsActive = 1)
	    
	select @TempID = BranchID from KPI_Branches (NOLOCK) where BranchName = 'BA'
	
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
			            when mtd.StatID in (15,16) then 0 
						else mtd.MonthToDate 
					end * case when stat.StatisticType = 4 then EUR else 1 end),0) AS [Value]
		from bodb_LicenseeReport.dbo.rptKPI_MTD_BA_Cross mtd (nolock)
			inner join @Sites sites on mtd.siteid = sites.SiteID
			inner join dbo.KPI_Groups g (NOLOCK) on sites.LicenseeID = g.SiteID
			inner join dbo.KPI_SectionStatistic ss (NOLOCK) ON mtd.StatID = ss.StatID
			inner join dbo.KPI_BranchGroup bg (NOLOCK) ON g.GroupID = bg.GroupID AND bg.BranchID = @TempID 
			left join dbo.KPI_Statistics stat on mtd.StatID = stat.StatID
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
	delete FROM #Result where StatID = 14
	
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
		SELECT t1.ReportDate,14 AS StatID,5,t1.GroupID,t1.BranchID,(t1.Value*0.03) AS SportRevenueTransaction
		FROM #Temp (NOLOCK) t1 
		WHERE t1.StatID = 7
	
	insert INTO #Result (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT t1.ReportDate,1100 AS StatID,5,t1.GroupID,t1.BranchID,t1.Value AS SportRevenueToTalInEUR
		FROM #Result (NOLOCK) t1 
		WHERE t1.StatID = 14
		
	insert INTO #Result (ReportDate,StatID,SectionID,GroupID,BranchID,Value)
		SELECT t1.ReportDate,1400 AS StatID,5,t1.GroupID,t1.BranchID,(t1.Value * oanda.MYR) AS SportRevenueToTalInMYR
		FROM #Result (NOLOCK) t1
		left join bodb02.dbo.Lrf_f_GetExchangeDaily(@FromDate,@ToDate) oanda on t1.ReportDate = oanda.exchangedate and oanda.exchangeid = 6
		WHERE t1.StatID = 1100
		
		
	select ReportDate,StatID,SectionID,GroupID,BranchID,Value
	from #Result (NOLOCK)
	order by ReportDate, BranchID, GroupID
	
	drop TABLE #Temp
	drop TABLE #Result


		

END


GO
GRANT EXECUTE ON [dbo].[KPI_GetReportData_BA] TO [bodbAdminNet] AS [dbo]
GO
GRANT EXECUTE ON [dbo].[KPI_GetReportData_BA] TO [bodbLicenseeNet] AS [dbo]
GO
GRANT VIEW DEFINITION ON [dbo].[KPI_GetReportData_BA] TO [vnteam] AS [dbo]