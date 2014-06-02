USE [bodb_Licensee]
GO
/****** Object:  StoredProcedure [dbo].[KPI_GetStatisticsConfig]    Script Date: 06/02/2014 05:19:19 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.KPI_GetStatisticsConfig    Script Date: 3/24/2014 11:12:45  ******/

ALTER PROCEDURE [dbo].[KPI_GetStatisticsConfig]   
	@ReportType int = -1,
	@BranchID int = -1,
	@StatID int = -1
AS  
  
/*  
 * Created by : 20140117@Francis 
 * Task  : Get the configuration of all Statistics for KPI report(KPI structural re-arrangement task) 
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 		20140214@Francis: Add IsActive filer for Statistic into Configuration
		20140324@Francis: Remove RNG Casino and Bingo restriction
 * Param's Explanation:    
 * 
 */  
 
BEGIN
	SET NOCOUNT ON  
	
	SELECT s.StatID , b.BranchID, se.SectionID, g.GroupID, b.ReportType, sc.IndexName, 
	   sc.StatisticName, sc.Template
	FROM KPI_Branches b INNER JOIN KPI_StatisticConfig sc
	   ON b.BranchID = sc.BranchID INNER JOIN KPI_SectionStatistic ss
	   ON sc.StatID = ss.StatID INNER JOIN KPI_Sections se
	   ON se.SectionID = ss.SectionID INNER JOIN KPI_BranchGroup bg
	   ON b.BranchID = bg.BranchID INNER JOIN KPI_Groups g
	   ON bg.GroupID = g.GroupID INNER JOIN KPI_Statistics s
	   ON sc.StatID = s.StatID
	WHERE ((@ReportType = -1) OR (@ReportType <> -1 AND b.ReportType = @ReportType))
	AND ((@BranchID = -1) OR (@BranchID <> -1 AND sc.BranchID = @BranchID))
	AND ((@StatID = -1) OR (@StatID <> -1 AND sc.StatID = @StatID))
	AND b.IsActive = 1 
	AND g.IsActive = 1 
	AND s.IsActive = 1
	ORDER BY b.BranchID ASC, g.OrderNo ASC, se.OrderNo ASC, s.OrderNo ASC
END