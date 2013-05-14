ALTER PROCEDURE [dbo].[OA_UserLicenseesProductGetByUserID]
	@UserID int,
	@ProductPrefix varchar(10)
AS
/*  
 * Created: 20111013@Henry
 * Task : get all licensee of UserID of a product
 * DB: DB052.bodb_Licensee  
 *  
 * Param's Explanation:
	+ @ProductPrefix: 
		- RB: Racebook
		- NG: Number Game
		- BA: Bet Aggregator
 * Revisions:     
 - 20120510@Henry: only get active Licensees
 - 20120704@Henry: Map Licensee with System
*/
SET NOCOUNT ON

DECLARE @ProductID INT

SELECT @ProductID = ProductID FROM Product3rd (NOLOCK)
WHERE ProductPrefix = @ProductPrefix

SELECT 	
	l.LicenseeID
	,l.LicenseeName
	,r.ResellerID
	,r.ResellerName
FROM(
	SELECT	gl.ResellerID,
		gl.LicenseeID
	FROM
		dbo.OA_GroupLicensees AS gl WITH(NOLOCK)		
		INNER JOIN dbo.OA_Users AS u WITH(NOLOCK) ON gl.GroupID=u.GroupID AND u.UserID = @UserID 
		
	UNION

	SELECT	ResellerID
		,LicenseeID
	FROM
		dbo.OA_UserLicensees WITH(NOLOCK)		
	WHERE
		UserID = @UserID		
	)AS t
	INNER JOIN dbo.Resellers AS r WITH(NOLOCK) ON r.ResellerID=t.ResellerID
	INNER JOIN dbo.Licensees AS l WITH(NOLOCK) ON l.LicenseeID=t.LicenseeID
	INNER JOIN dbo.LicenseeProduct3rd AS lp WITH (NOLOCK) ON lp.LicenseeID = l.LicenseeID AND ProductID = @ProductID
	INNER JOIN SystemLicensee sl (NOLOCK) ON l.LicenseeID=sl.LicenseeID 
	INNER JOIN Systems s (NOLOCK) ON sl.SystemID=s.ID 
WHERE 	
	isnull(@ProductID,0)<>0
	AND sl.IsActive = 1
	AND s.SystemName='OA'
	AND
	(
		(@ProductID = 3 AND r.ResellerID = 3)
		OR
		(@ProductID <> 3 AND r.ResellerID <> 3)
	)
	
GO
GRANT EXECUTE ON [dbo].[OA_UserLicenseesProductGetByUserID] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_UserLicenseesProductGetByUserID] TO [vnteam] 