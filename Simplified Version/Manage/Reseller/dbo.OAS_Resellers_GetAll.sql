ALTER PROCEDURE [dbo].[OAS_Resellers_GetAll]   
	@Fromdate SMALLDATETIME,
	@Todate   SMALLDATETIME	
AS  
  
/*  
 * Created by : [20111220@Kos]  
 * Task  : Get all resellers  
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 20120319@Henry: hard-code Boping to not show 
 20120621@Jim: optimize code
 20130724@Jim:  PIH and Starlit are no longer ONEWorks licensees since July 1st 2013
 20130829@Jim: Remove Cozni from licensee list in Total Transaction report from 1st August 2013.
 20130905@Jim:Boping is no longer ONEWorks licensee since August 1st 2013
 20130923@Victor: Starlit becomes FDL (BA) from Aug 1st 2013, Remove Direct Licensees from the list
 */  
  
SET NOCOUNT ON  

SELECT @Fromdate=ltrim(rtrim(@Fromdate)),@Todate=ltrim(rtrim(@Todate))  
SELECT   
	DISTINCT
	 r.ResellerID,  
	 r.ResellerName,  
	 r.Description,  
	 r.ResellerType  
	INTO #tmpResellerList 
FROM dbo.Resellers r WITH (NOLOCK)   
INNER JOIN LicenseeReseller lr WITH (NOLOCK) ON r.ResellerID = lr.ResellerID
INNER JOIN SystemLicensee sl (NOLOCK) ON lr.LicenseeID=sl.LicenseeID 
INNER JOIN Systems s (NOLOCK) ON sl.SystemID=s.ID 
WHERE 
	sl.IsActive=1
	AND s.SystemName='OAS'

-- Remove Starlit, PIH, Boping, Cozni by date range
DELETE FROM #tmpResellerList 
WHERE (@FromDate BETWEEN '2013-07-01' AND '2013-07-31' AND ResellerID IN (3,8))
	  OR (@FromDate>='2013-08-01' AND ResellerID IN (5,7,8))

-- Remove direct licensees
DECLARE @DirectLics TABLE (ResellerID INT)

INSERT INTO @DirectLics
SELECT DISTINCT r.ResellerID 
FROM LicenseeReseller lr (NOLOCK)
	INNER JOIN Resellers r (NOLOCK) ON lr.ResellerID = r.ResellerID
	INNER JOIN Licensees l (NOLOCK) ON l.LicenseeID = lr.LicenseeID
WHERE 
	l.LicenseeName = r.ResellerName

DELETE FROM #tmpResellerList WHERE ResellerID IN (SELECT ResellerID FROM @DirectLics)

SELECT 
	ResellerID,  
	CASE WHEN (ResellerID = 3 AND @FromDate>='2013-08-01') THEN 'BA (FDL)' ELSE ResellerName END AS ResellerName,  
	Description,  
	ResellerType 
FROM #tmpResellerList
DROP TABLE #tmpResellerList
GO
GRANT EXECUTE ON [dbo].[OAS_Resellers_GetAll] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Resellers_GetAll] TO [vnteam]        
  