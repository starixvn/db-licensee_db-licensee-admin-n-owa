USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[KPI_GetAllGroups]    Script Date: 6/9/2014 16:55:07  ******/
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
   -20140529@Francis: Add BrandName (if exists) for each Group
 * Param's Explanation:    
 * 
 */  
 
BEGIN
	SET NOCOUNT ON  
	
	SELECT g.GroupID, 
		   CASE WHEN l.BrandName IS NOT NULL AND l.BrandName <> '' AND l.BrandName <> ' '
				THEN g.GroupName + ' (' + l.BrandName + ')'
		   ELSE
				g.GroupName
		   END	
		   AS GroupName, 
		   g.GroupType, g.RelatedBranch, g.OrderNo
	FROM KPI_Groups g (NOLOCK) 
	     LEFT JOIN Licensees l (NOLOCK) ON g.SiteID = l.LicenseeID
	WHERE ((@GroupID = 0) OR (@GroupID <> 0 AND g.GroupID = @GroupID))
	AND ((@GroupType = -1) OR (@GroupType <> -1 AND g.GroupType = @GroupType))
	AND g.IsActive = 1
	OR (g.IsActive = 0 AND g.GroupID = 55)
END








