USE [bodb_licensee]
GO
 
ALTER PROCEDURE [dbo].[OA_FunctionLicenseesGetByFunctionID]
	@FunctionID int
AS
/*  
 * Created: 20110909@Kos
 * Task : get licensee(s) of a function
 * DB: DB052.bodb_Licensee  
 *  
 * Revisions:     
 - 20120510@Henry: only get active Licensees
 - 20120704@Henry: Map Licensee with System
 - 20140228@Jim: hard-code to hide Credit Licensee and test licensee in some report : Licensee Win Loss,Currency Win Loss Report,Racing 
*/
SET NOCOUNT ON


SELECT	
	r.ResellerID
	,r.ResellerName
	,r.Description AS ResellerDescription
	,l.LicenseeID
	,l.LicenseeName
	,l.Description AS LicenseeDescription
FROM
	dbo.OA_FunctionLicensees AS gl WITH(NOLOCK)
	INNER JOIN dbo.Resellers AS r WITH(NOLOCK) ON gl.ResellerID=r.ResellerID
	INNER JOIN dbo.Licensees AS l WITH(NOLOCK) ON gl.LicenseeID=l.LicenseeID
	INNER JOIN SystemLicensee sl (NOLOCK) ON l.LicenseeID=sl.LicenseeID 
	INNER JOIN Systems s (NOLOCK) ON sl.SystemID=s.ID
WHERE
	(	
		(r.ResellerID not in (4,8) and l.LicenseeID<> 5 and @FunctionID in (7,11,20,24,25,26) ) 
		OR (FunctionID = @FunctionID and @FunctionID not in (7,11,20))
	)
	AND sl.IsActive = 1
	AND s.SystemName='OA'

GO
GRANT EXECUTE ON [dbo].[OA_FunctionLicenseesGetByFunctionID] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_FunctionLicenseesGetByFunctionID] TO [vnteam]		