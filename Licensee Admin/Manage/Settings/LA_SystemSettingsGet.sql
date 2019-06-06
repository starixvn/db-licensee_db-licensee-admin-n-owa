/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE dbo.LA_SystemSettingsGet
	@Key		VARCHAR(100)
AS
/*	Created: 20181203@Parsons
	Task: LA-Licensee Performance Alert
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20181203@Parsons: LA - Licensee Performance Alert [#104918]

	Param's Explanation:
	EXEC LA_SystemSettingsGet 'LicenseePerformanceAlert'
*/
BEGIN
	SET NOCOUNT ON;

	SELECT [Value]
	FROM dbo.LA_SystemSettings WITH(NOLOCK)
	WHERE @Key = [Key]
END
GO