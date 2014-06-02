USE [bodb_licensee]
GO

/****** Object:  StoredProcedure [dbo].[KPI_GetAllGroups]    Script Date: 6/2/2014 16:10:39  ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


ALTER PROCEDURE [dbo].[KPI_GetAllGroups]   
	@GroupID int = 0,
	@GroupType int = -1
AS  
  
/*  
 * Created by : 20140117@Francis 
 * Task  : Get all groups for KPI report(KPI structural re-arrangement task) 
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
   -20140529@Francis: Add BranchName (if exists) for each Group
 * Param's Explanation:    
 * 
 */  
 
BEGIN
	SET NOCOUNT ON  
	
	SELECT GroupID, 
		   CASE WHEN BrandName IS NOT NULL AND BrandName <> '' AND BrandName <> ' '
				THEN GroupName + ' (' + BrandName + ')'
		   ELSE
				GroupName
		   END	
		   AS GroupName, 
		   GroupType, RelatedBranch, OrderNo
	FROM KPI_Groups g (NOLOCK) 
	     LEFT JOIN Licensees l (NOLOCK) ON g.SiteID = l.LicenseeID
	WHERE ((@GroupID = 0) OR (@GroupID <> 0 AND GroupID = @GroupID))
	AND ((@GroupType = -1) OR (@GroupType <> -1 AND GroupType = @GroupType))
	AND IsActive = 1
END



