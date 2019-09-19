/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_UserSettingIns]
	@UserId			INT,
	@Data			VARCHAR(8000),
	@FunctionKey	NVARCHAR(100),
	@Name			NVARCHAR(50),
	@ErrCode		INT				= 0		OUTPUT, 
	@ErrMsg			VARCHAR(4000)	= ''	OUTPUT
AS
/*
	Created: 20190911@Parsons
	Task : Save query filters in LPID report [#FeatureId 119536]
	DB: DBCUST.bodb_Licensee

	Revisions:
	- 20190911@Parsons: add new sp

	Param's Explannation: 
*/
BEGIN
	SET NOCOUNT ON

	IF (@UserId <= 0 OR @Data = '' OR @FunctionKey = '' OR @Name = '') 
	BEGIN
		SELECT @ErrMsg = 'Setting is invalid, Please check again.', @ErrCode =  505
		RETURN
	END

	IF EXISTS (SELECT TOP 1 1 FROM [dbo].[LA_UserSettings] WITH(NOLOCK) WHERE UserId = @UserId AND FunctionKey = @FunctionKey AND [Name] = @Name) 
	BEGIN
		SELECT @ErrMsg = 'User''s setting has been exists with name('+ @Name +').', @ErrCode =  507
		RETURN
	END

	INSERT INTO [dbo].[LA_UserSettings] (UserId, FunctionKey, [Name], [Data])
	VALUES(@UserId, @FunctionKey, @Name, @Data)
END
GO