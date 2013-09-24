SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE OAS_Licensee_BALicenseeSel
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
  

*/

BEGIN
	SET NOCOUNT ON

	SELECT l.LicenseeID, L.LicenseeName
	FROM LicenseeProduct3rd lp
		INNER JOIN Licensees L ON L.LicenseeID = lp.LicenseeID
	WHERE lp.ProductID = 3
		AND lp.EffectiveDate IS NOT NULL AND lp.EffectiveDate <= @ToDate
		AND L.AffectedDate IS NOT NULL AND l.AffectedDate <= @ToDate
END
GO

GRANT EXECUTE ON [dbo].[OAS_Licensee_BALicenseeSel] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Licensee_BALicenseeSel] TO vnteam
GO