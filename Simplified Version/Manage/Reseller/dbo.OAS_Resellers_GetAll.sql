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

DELETE FROM #tmpResellerList 
WHERE (@FromDate BETWEEN '2013-07-01' AND '2013-07-30' AND ResellerID IN (3,8))
	  OR (@FromDate>='2013-08-01' AND ResellerID IN (3,5,8))

SELECT 
	ResellerID,  
	ResellerName,  
	Description,  
	ResellerType 
FROM #tmpResellerList
DROP TABLE #tmpResellerList
GO
GRANT EXECUTE ON [dbo].[OAS_Resellers_GetAll] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Resellers_GetAll] TO [vnteam]        
  