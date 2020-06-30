/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

CREATE PROCEDURE [dbo.LA_GroupMinFeeHeaderIns]
	@GroupName	NVARCHAR(110),
	@FromDate	DATE,
	@ToDate		DATE,
	@ErrCode	INT				= 0		OUTPUT, 
	@ErrMsg		VARCHAR(4000)	= ''	OUTPUT
AS
/*
	Created: 20190107@Parsons
	Task : Launch new licensee
	DB: DBCUST.bodb_Licensee

	Revisions:
	- 20190107@Parsons: Launch new licensee

	Param's Explannation: 

*/
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    -- Insert statements for procedure here
	SELECT <@Param1, sysname, @p1>, <@Param2, sysname, @p2>
END
GO
