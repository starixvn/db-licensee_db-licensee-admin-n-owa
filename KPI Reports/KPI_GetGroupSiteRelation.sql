USE [bodb_Licensee]
GO
/****** Object:  StoredProcedure [dbo].[KPI_GetGroupSiteRelation]    Script Date: 06/02/2014 05:18:14 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.KPI_GetGroupSiteRelation    Script Date: 3/26/2014 17:46:01  ******/

ALTER PROCEDURE [dbo].[KPI_GetGroupSiteRelation]   
	@BranchType varchar(50) = '4,5'
AS  

/*  
 * Created by : 20140305@Francis 
 * Task  : Get mapping between sites and groups in KPI report for RNG and Bingo (default)
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
   - 20140305@Francis: Change 18bb and IBC to PIH and FDL
   - 20140326@Francis: Add unactive Licensees
   - 20140326@Francis: Cast IsActive to BIT datatype
 * Param's Explanation:    
 * 
 */  
 
BEGIN
	SET NOCOUNT ON  
	
	SELECT DISTINCT
           b.BranchID,
           b.BranchType,
           g.GroupID,
           CASE WHEN l.LicenseeName = '18bb' THEN r.ResellerName
				WHEN l.LicenseeName = 'IBC' THEN r.ResellerName
				ELSE l.LicenseeName
				END
           AS SiteName,
		   CAST(1 AS BIT) AS IsActive
	FROM dbo.Resellers AS r WITH (NOLOCK) INNER JOIN
		 dbo.LicenseeReseller AS lr WITH (NOLOCK) ON r.ResellerID = lr.ResellerID LEFT OUTER JOIN
         dbo.Licensees AS l WITH (NOLOCK) ON lr.LicenseeID = l.LicenseeID LEFT OUTER JOIN
         dbo.Labels AS lbl WITH (NOLOCK) ON lr.LicenseeID = lbl.LicenseeID LEFT OUTER JOIN
         dbo.SystemLicensee AS syslic WITH (NOLOCK) ON lr.LicenseeID = syslic.LicenseeID INNER JOIN
         dbo.KPI_Groups AS g WITH (NOLOCK) ON l.LicenseeID = g.SiteID INNER JOIN
         dbo.KPI_BranchGroup AS bg WITH (NOLOCK) ON bg.GroupID = g.GroupID INNER JOIN
         dbo.KPI_Branches AS b WITH (NOLOCK) ON bg.BranchID = b.BranchID
	WHERE (lr.ResellerID NOT IN (6,3)) AND (syslic.SystemID = 5) AND (syslic.IsActive = 1)
		  AND g.IsActive = 1
		  AND b.BranchType IN (SELECT VAL FROM bodb02.dbo.strSplit(@BranchType,','))
	UNION
	SELECT -1 AS BranchID,
		   -1 AS BranchType,
		   -1 AS GroupID,
		   LicenseeName AS SiteName,
		   CAST(0 AS BIT) AS IsActive
	FROM Licensees ss WITH (NOLOCK)
	WHERE ss.LicenseeID NOT IN 
						(
							SELECT DISTINCT	l.LicenseeID
							FROM dbo.Resellers AS r WITH (NOLOCK) INNER JOIN
								 dbo.LicenseeReseller AS lr WITH (NOLOCK) ON r.ResellerID = lr.ResellerID LEFT OUTER JOIN
								 dbo.Licensees AS l WITH (NOLOCK) ON lr.LicenseeID = l.LicenseeID LEFT OUTER JOIN
								 dbo.Labels AS lbl WITH (NOLOCK) ON lr.LicenseeID = lbl.LicenseeID LEFT OUTER JOIN
								 dbo.SystemLicensee AS syslic WITH (NOLOCK) ON lr.LicenseeID = syslic.LicenseeID INNER JOIN
								 dbo.KPI_Groups AS g WITH (NOLOCK) ON l.LicenseeID = g.SiteID INNER JOIN
								 dbo.KPI_BranchGroup AS bg WITH (NOLOCK) ON bg.GroupID = g.GroupID INNER JOIN
								 dbo.KPI_Branches AS b WITH (NOLOCK) ON bg.BranchID = b.BranchID
							WHERE (lr.ResellerID NOT IN (6,3)) AND (syslic.SystemID = 5) AND (syslic.IsActive = 1)
								 AND g.IsActive = 1
								 AND b.BranchType IN (SELECT VAL FROM bodb02.dbo.strSplit(@BranchType,','))
						)
	ORDER BY IsActive DESC, b.BranchID ASC
END