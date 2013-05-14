ALTER PROCEDURE [dbo].[OAS_Resellers_GetAll]   
AS  
  
/*  
 * Created by : [20111220@Kos]  
 * Task  : Get all resellers  
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 20120319@Henry: hard-code Boping to not show 
 20120621@Jim: optimize code
 */  
  
SET NOCOUNT ON  
  
SELECT   
	DISTINCT
	 r.ResellerID,  
	 r.ResellerName,  
	 r.Description,  
	 r.ResellerType  
FROM dbo.Resellers r WITH (NOLOCK)   
INNER JOIN LicenseeReseller lr WITH (NOLOCK) ON r.ResellerID = lr.ResellerID
INNER JOIN SystemLicensee sl (NOLOCK) ON lr.LicenseeID=sl.LicenseeID 
INNER JOIN Systems s (NOLOCK) ON sl.SystemID=s.ID 
WHERE 
sl.IsActive=1
AND s.SystemName='OAS'

GO
GRANT EXECUTE ON [dbo].[OAS_Resellers_GetAll] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Resellers_GetAll] TO [vnteam]        
  