/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE PROCEDURE [dbo].[LA_LicenseeGroupAssignmentSel]
AS
/*  
	 Created: 20190514@Bruce[#111587]
	 Task : Manage licensee group
	 DB: DBLIC.bodb_licensee   

	 Revisions:  
		- 20190514@Bruce: Create SP

*/
BEGIN
	SET NOCOUNT ON;
	
	SELECT p.PartyId, p.PartyName, pd.BrandName, ISNULL(a.GroupId, 0) AS GroupId
	FROM dbo.OAS_Party p WITH(NOLOCK)
	INNER JOIN dbo.OAS_PartyDetail pd WITH(NOLOCK) ON p.PartyID=pd.PartyID
	LEFT JOIN dbo.LA_CombinedGroupAssignment a WITH(NOLOCK) ON p.PartyId = a.PartyId
	WHERE p.PartyType = 1 AND pd.IsDeposit = 1 AND pd.StatusId = 1
END
