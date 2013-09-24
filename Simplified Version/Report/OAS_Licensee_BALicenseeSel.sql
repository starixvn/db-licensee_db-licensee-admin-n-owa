SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE OAS_Licensee_BALicenseeSel
(
	@FromDate DATETIME,
	@ToDate DATETIME
)
AS

/*
Created: Victor@20130920
Task : Change to backend report F5629
DB: DB052.bodb_licensee
Original: [OAS_Licensee_BALicenseeSel]
Params explanation:
Revisions:  
  20130924@Victor: Remove Boping&Cozni licensees

*/

BEGIN
	SET NOCOUNT ON

	DECLARE @tmpLicensee TABLE (LicenseeID INT)
	INSERT INTO @tmpLicensee
	SELECT lr1.LicenseeID FROM LicenseeReseller lr1 (NOLOCK) WHERE lr1.ResellerID IN (5,7)

	SELECT l.LicenseeID, L.LicenseeName
	FROM LicenseeProduct3rd lp (NOLOCK)
		INNER JOIN Licensees L (NOLOCK) ON L.LicenseeID = lp.LicenseeID
		INNER JOIN SystemLicensee sl (NOLOCK) ON sl.LicenseeID = L.LicenseeID
		INNER JOIN Systems s (NOLOCK) ON sl.SystemID=s.ID 
	WHERE lp.ProductID = 3
		AND s.SystemName LIKE 'OAS'
		AND (L.AffectedDate IS NULL OR l.AffectedDate <= @ToDate)
		AND L.LicenseeID NOT IN (SELECT LicenseeID FROM @tmpLicensee)
END
GO

GRANT EXECUTE ON [dbo].[OAS_Licensee_BALicenseeSel] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Licensee_BALicenseeSel] TO vnteam
GO