/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].LA_Statement_SOAFileGet
	@SOAId INT
AS
/*	Created: 20190121@Danny
	Task : Get SOA pdf from DB
	DB: DBCUST.bodb_Licensee
	
	Revisions:
		- 20240409@Danny: Create SP [#96660]
*/

BEGIN
	SET NOCOUNT ON;
	SELECT FileData FROM dbo.LA_SOAFile WITH(NOLOCK) WHERE SOAId = @SOAId
END
GO