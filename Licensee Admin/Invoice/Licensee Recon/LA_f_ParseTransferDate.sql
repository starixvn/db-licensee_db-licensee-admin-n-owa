/*<info serverAlias="DBACC-bodb02" selecters="bodbAdminNet" isFunction="1" isNested="1"></info>*/
USE bodb02
GO

ALTER FUNCTION [dbo].[LA_f_ParseTransferDate](@Remark VARCHAR(150))
/*  
	Created: 20190814@Bruce
	Task : Parse transfer date in remark
	DB: DBACC.bodb02
	
	Revisions:
		- 20190814@Bruce: create function [#111586]

*/
RETURNS DATE
AS
BEGIN
	DECLARE @i INT = (SELECT TOP 1 id FROM dbo.strSplit(@Remark, ' ') WHERE val LIKE '[0-9][0-9][0-9][0-9])' ORDER BY id DESC)
	DECLARE @value VARCHAR(20) = '01' + SUBSTRING(@Remark,@i - 11, 9)
	
	RETURN CONVERT(DATE ,@value, 106);
END
GO