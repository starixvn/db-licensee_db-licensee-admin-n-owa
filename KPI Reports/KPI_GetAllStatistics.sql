USE [bodb_licensee]
GO

/****** Object:  StoredProcedure [dbo].[KPI_GetAllStatistics]    Script Date: 6/2/2014 16:11:07  ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




ALTER PROCEDURE [dbo].[KPI_GetAllStatistics]   
	@StatID int = 0,
	@StatisticType int = -1
AS  
  
/*  
 * Created by : 20140117@Francis 
 * Task  : Get all statistics for KPI report(KPI structural re-arrangement task) 
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 	
 * Param's Explanation:    
 * 
 */  
 
BEGIN
	SET NOCOUNT ON  
	
	SELECT StatID, StatisticType, MathType, OrderNo
	FROM KPI_Statistics (NOLOCK)
	WHERE ((@StatID = 0) OR (@StatID <> 0 AND StatID = @StatID))
	AND ((@StatisticType = -1) OR (@StatisticType <> -1 AND StatisticType = @StatisticType))
	AND IsActive = 1
END



