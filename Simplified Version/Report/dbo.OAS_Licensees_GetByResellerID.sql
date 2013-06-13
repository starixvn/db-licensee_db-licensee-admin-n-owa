set ANSI_NULLS ON
set QUOTED_IDENTIFIER ON
go

ALTER PROCEDURE [dbo].[OAS_Licensees_GetByResellerID]   
	@ResellerID INT = 0,
	@ExcludeBA BIT = 0,
	@ExcludeTest BIT = 1,
	@ProductCode VARCHAR(10)=''
AS  
  
/*  
 * Created by : [20111220@Kos]  
 * Task  : Get all licensees of a reseller  
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 *  
	- 20120319@Henry: hard-code Boping to not show 
	- 20120510@Henry: only get licensees which have IsOneWorkActive=1
	- 20120621@Jim: optimize code 
	- 20120828@Henry: add 2 more params @ExcludeBA and @ExcludeTest
	- 20120917@Henry: add param @ProductCode
	- 20130222@Scott: add filter LicenseeProduct3rd.EffectiveDate <> null
 * Param's Explanation:    
 *  - @ResellerID : Reseller ID (0 : All reseller)  
 *	- @ExcludeBA: to exclude BA Licensees (Starlit)
 *	- @ExcludeTest: to exclude Spondemo (a test licensee)
 */  
  
SET NOCOUNT ON  

CREATE TABLE #Data (ResellerID int,ResellerName varchar(50), ResellerType INT,ResellerDescription varchar(100),LicenseeID INT, LicenseeName varchar(50),LicenseeDescription varchar(100))
DECLARE @ProductID INT
  
INSERT INTO #Data  (ResellerID,ResellerName, ResellerType,ResellerDescription,LicenseeID, LicenseeName,LicenseeDescription)
SELECT  
	r.ResellerID,  
	r.ResellerName,  
	r.ResellerType,
	r.Description AS ResellerDescription,  
	l.LicenseeID,  
	l.LicenseeName,
	l.Description AS LicenseeDescription
FROM   
	dbo.Licensees AS l WITH (NOLOCK)   
	INNER JOIN dbo.LicenseeReseller AS ls WITH (NOLOCK) ON l.LicenseeID = ls.LicenseeID AND (@ResellerID = 0 OR ls.ResellerID = @ResellerID)  
	INNER JOIN dbo.Resellers AS r WITH (NOLOCK)	ON r.ResellerID = ls.ResellerID  
	INNER JOIN SystemLicensee sl (NOLOCK) ON l.LicenseeID=sl.LicenseeID 
	INNER JOIN Systems s (NOLOCK) ON sl.SystemID=s.ID 
	INNER JOIN dbo.LicenseeProduct3rd ld WITH (NOLOCK) ON l.LicenseeID=ld.LicenseeID
WHERE 
	(
		l.IsDeposit = 1  
		OR  
		(
			l.IsDeposit=0 AND l.LicenseeID IN (SELECT DISTINCT LicenseeID FROM Labels WITH (NOLOCK))
		)
	)
	AND sl.IsActive=1
	AND s.SystemName='OAS'
	AND ((@ExcludeBA=0) OR (@ExcludeBA=1 AND r.ResellerID <> 3))
	AND ((@ExcludeTest=0) OR (@ExcludeTest=1 AND r.ResellerID <> 6))
	AND ISNULL(ld.EffectiveDate,0)<>0
ORDER BY l.IsDeposit DESC,r.ResellerName, l.LicenseeName

SET @ProductCode = ISNULL(LTRIM(RTRIM(@ProductCode)),'')
IF @ProductCode <> '' AND EXISTS(SELECT 1 FROM Product3rd WITH (NOLOCK) WHERE ProductPrefix = @ProductCode)
BEGIN
	IF @ProductCode<> 'BA'
	BEGIN
		DELETE FROM #Data WHERE ResellerID = 3
		SELECT @ProductID = ProductID FROM Product3rd WITH (NOLOCK) WHERE ProductPrefix = @ProductCode
		
		DELETE FROM #Data WHERE LicenseeID NOT IN (SELECT LicenseeID FROM LicenseeProduct3rd WITH (NOLOCK) WHERE ProductID=@ProductID) AND ResellerID NOT IN (4,8) --FDL, PIH
	END
	ELSE
	BEGIN
		DELETE FROM #Data WHERE ResellerID <> 3
	END

END

SELECT DISTINCT * FROM #Data

DROP TABLE #Data

GO
GRANT EXECUTE ON [dbo].[OAS_Licensees_GetByResellerID] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Licensees_GetByResellerID] TO [vnteam]        
  

