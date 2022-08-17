/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_LicenseeGroupAssignmentSel]
	@PartyIds NVARCHAR(MAX) = ''
	,@IsActive BIT 
AS
/*  
	 Created: 20190514@Bruce[#111587]
	 Task : Manage licensee group
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20190514@Bruce: Create SP
		- 20220817@Malcolm: LA - Enhance Manage Licensee Group [RedmineId : #176437]
*/
BEGIN
	SET NOCOUNT ON;

	SELECT @IsActive = ISNULL(@IsActive, 0), @PartyIds = ISNULL(@PartyIds, '')

	DECLARE @Party TABLE (PartyId INT PRIMARY KEY)

	INSERT INTO @Party (PartyId)
	SELECT DISTINCT f.value
	FROM STRING_SPLIT(@PartyIds, ',') f
	
	SELECT 
		p.PartyId
		,p.PartyName
		,pd.BrandName
		,ISNULL(a.GroupId, 0) AS GroupId
		,ISNULL(a.GroupType, 0) AS GroupType
		,CASE WHEN pd.TerminatedDate IS NOT NULL THEN 'Terminated'
			  WHEN pd.SuspendedDate IS NOT NULL THEN 'Suspended'
		 ELSE 'Active' END AS [Status]
	FROM dbo.OAS_Party p WITH(NOLOCK)
		INNER JOIN dbo.OAS_PartyDetail pd WITH(NOLOCK) ON p.PartyID=pd.PartyID
		LEFT JOIN dbo.LA_CombinedGroupAssignment a WITH(NOLOCK) ON p.PartyId = a.PartyId
	WHERE p.PartyType = 1 AND pd.IsDeposit = 1 AND pd.StatusId = 1
		AND (@PartyIds = '' OR p.PartyId IN (SELECT PartyId FROM @Party))
		AND (@IsActive = 0 OR @IsActive = 1 AND pd.SuspendedDate IS NULL AND pd.TerminatedDate IS NULL)
END
GO